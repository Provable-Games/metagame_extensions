// SPDX-License-Identifier: BUSL-1.1

/// MerklePrize — sponsor commits to a merkle root of (account, amount) leaves
/// at `add_prize` time; recipients later `claim_prize` by submitting their
/// (amount, proof) and receive the corresponding ERC20 payout. Designed for
/// arbitrary off-chain ranking, partner airdrops, and any case where the
/// recipient list is too large or too dynamic to materialize on-chain.
///
/// Storage is namespaced by `(context_owner, context_id)` per the
/// `PrizeExtensionComponent` contract: a tournament platform like Budokan
/// can host multiple independent prizes on the same MerklePrize deployment.
///
/// Sponsor responsibilities
/// ------------------------
/// 1. Build the merkle tree off-chain using OpenZeppelin's StandardMerkleTree
///    format over `[account, amount_low, amount_high]` leaves (Pedersen hash).
/// 2. Transfer `total_amount` of `token_address` to this contract address
///    before any winner attempts to claim — the extension does NOT escrow on
///    `add_prize`. Underfunding strands valid claims at `transfer` time.
/// 3. Submit the prize with config = `[token_address, root]`.
///
/// Config layout (`add_prize`):     [token_address, merkle_root]
/// Claim params (`claim_prize`):    [account, amount_low, amount_high, ...proof]   (prize_id is a
/// top-level arg)

#[starknet::interface]
pub trait IMerklePrize<TState> {
    /// Returns the stored merkle root for `(context_owner, context_id, prize_id)`
    /// or zero if unset.
    fn get_root(
        self: @TState, context_owner: starknet::ContractAddress, context_id: u64, prize_id: u64,
    ) -> felt252;

    /// Returns true if `account` has already claimed against this prize.
    fn is_claimed(
        self: @TState,
        context_owner: starknet::ContractAddress,
        context_id: u64,
        prize_id: u64,
        account: starknet::ContractAddress,
    ) -> bool;
}

#[starknet::contract]
pub mod merkle_prize {
    use core::hash::HashStateTrait;
    use core::pedersen::PedersenTrait;
    use metagame_extensions_prize::prize_extension_component::PrizeExtensionComponent;
    use metagame_extensions_prize::prize_extension_component::PrizeExtensionComponent::PrizeExtension;
    use openzeppelin_interfaces::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_merkle_tree::merkle_proof;
    use starknet::ContractAddress;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use super::IMerklePrize;

    component!(path: PrizeExtensionComponent, storage: prize, event: PrizeEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl PrizeExtensionImpl =
        PrizeExtensionComponent::PrizeExtensionImpl<ContractState>;
    impl PrizeExtensionInternalImpl = PrizeExtensionComponent::InternalImpl<ContractState>;
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        prize: PrizeExtensionComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        /// ERC20 token contract per prize.
        prize_token: Map<(ContractAddress, u64, u64), ContractAddress>,
        /// Merkle root committing to (account, amount) leaves.
        prize_root: Map<(ContractAddress, u64, u64), felt252>,
        /// Per-(prize, account) claim flag. Prevents double-claim and
        /// scopes the namespace so different prizes against the same
        /// account can be claimed independently.
        prize_claimed: Map<(ContractAddress, u64, u64, ContractAddress), bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        PrizeEvent: PrizeExtensionComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.prize.initializer();
    }

    /// Compute the OpenZeppelin StandardMerkleTree leaf hash for
    /// `[account, amount_low, amount_high]`. Format mirrors the merkle
    /// entry-requirement validator's `compute_leaf_hash` so the same JS
    /// tooling (StandardMerkleTree.of, getProof) produces compatible proofs.
    fn compute_leaf_hash(account: ContractAddress, amount: u256) -> felt252 {
        let amount_low: felt252 = amount.low.into();
        let amount_high: felt252 = amount.high.into();
        let leaf_value = PedersenTrait::new(0)
            .update(account.into())
            .update(amount_low)
            .update(amount_high)
            .update(3)
            .finalize();
        let inner = PedersenTrait::new(0).update(leaf_value).update(1).finalize();
        PedersenTrait::new(0).update(inner).finalize()
    }

    #[abi(embed_v0)]
    impl MerklePrizeViewImpl of IMerklePrize<ContractState> {
        fn get_root(
            self: @ContractState, context_owner: ContractAddress, context_id: u64, prize_id: u64,
        ) -> felt252 {
            self.prize_root.read((context_owner, context_id, prize_id))
        }

        fn is_claimed(
            self: @ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            prize_id: u64,
            account: ContractAddress,
        ) -> bool {
            self.prize_claimed.read((context_owner, context_id, prize_id, account))
        }
    }

    impl MerklePrizeExtensionImpl of PrizeExtension<ContractState> {
        fn add_prize(
            ref self: ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            prize_id: u64,
            config: Span<felt252>,
        ) {
            assert!(config.len() == 2, "MerklePrize: config must be [token, root]");
            let token: ContractAddress = (*config.at(0)).try_into().unwrap();
            let root: felt252 = *config.at(1);
            assert!(root != 0, "MerklePrize: root cannot be zero");

            let key = (context_owner, context_id, prize_id);
            assert!(self.prize_root.read(key) == 0, "MerklePrize: prize already configured");
            self.prize_token.write(key, token);
            self.prize_root.write(key, root);
        }

        fn get_config(
            self: @ContractState, context_owner: ContractAddress, context_id: u64, prize_id: u64,
        ) -> Span<felt252> {
            // Re-serialize the stored fields back to the original
            // `[token_address, merkle_root]` shape passed to add_prize.
            // Returns an empty span when the prize is unknown (root is
            // zero, which add_prize rejects so this is unambiguous).
            let key = (context_owner, context_id, prize_id);
            let root = self.prize_root.read(key);
            if root == 0 {
                return array![].span();
            }
            let token = self.prize_token.read(key);
            array![token.into(), root].span()
        }

        fn claim_prize(
            ref self: ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            prize_id: u64,
            claim_params: Span<felt252>,
        ) {
            assert!(
                claim_params.len() >= 3,
                "MerklePrize: claim_params must be [account, amount_low, amount_high, ...proof]",
            );
            let account: ContractAddress = (*claim_params.at(0)).try_into().unwrap();
            let amount_low: u128 = (*claim_params.at(1)).try_into().unwrap();
            let amount_high: u128 = (*claim_params.at(2)).try_into().unwrap();
            let amount = u256 { low: amount_low, high: amount_high };
            let proof = claim_params.slice(3, claim_params.len() - 3);

            let key = (context_owner, context_id, prize_id);
            let root = self.prize_root.read(key);
            assert!(root != 0, "MerklePrize: prize not configured");

            let claim_key = (context_owner, context_id, prize_id, account);
            assert!(!self.prize_claimed.read(claim_key), "MerklePrize: already claimed");

            let leaf = compute_leaf_hash(account, amount);
            assert!(merkle_proof::verify_pedersen(proof, root, leaf), "MerklePrize: invalid proof");

            self.prize_claimed.write(claim_key, true);

            let token = self.prize_token.read(key);
            let erc20 = IERC20Dispatcher { contract_address: token };
            assert!(erc20.transfer(account, amount), "MerklePrize: ERC20 transfer failed");
        }
    }
}
