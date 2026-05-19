// SPDX-License-Identifier: BUSL-1.1

/// NFTPrize — sponsor escrows a set of ERC721 token IDs assigned to specific
/// positions of a prize. The host (e.g. budokan) decides who receives each
/// position (typically the leaderboard winner at that rank, or the sponsor
/// when no winner qualifies) and tells this contract via `payout_prize`;
/// this contract is just an escrow manager that transfers the right NFT
/// to the right recipient.
///
/// This is the leaderboard-aware counterpart to the built-in single-ERC721
/// prize path: the built-in flow can hold at most one NFT per prize, while
/// this preset distributes N NFTs across N positions in one prize.
///
/// Sponsor responsibilities
/// ------------------------
/// 1. Transfer each of the assigned NFTs to this contract's address *before*
///    submitting the prize. The extension does NOT escrow on `add_prize`
///    because it cannot see the original sponsor — in the cross-contract
///    extension-dispatch model, `get_caller_address()` resolves to the host
///    contract, not the EOA that initiated the transaction. The contract
///    verifies ownership of each declared token ID at registration time
///    (sanity check) and rejects underfunded prizes.
/// 2. Submit the prize with config = `[token_address, num_positions,
///    token_id_0_low, token_id_0_high, token_id_1_low, token_id_1_high, ...]`.
///    `num_positions` MUST equal the number of (low, high) pairs following.
///
/// Config layout (`add_prize`):
///   [token_address, num_positions, id_0_low, id_0_high, id_1_low, id_1_high, ...]
/// Payout params (`payout_prize`): []   (position + recipient are top-level args)

#[starknet::interface]
pub trait INFTPrize<TState> {
    fn get_token_address(
        self: @TState, context_owner: starknet::ContractAddress, context_id: u64, prize_id: u64,
    ) -> starknet::ContractAddress;

    fn get_position_token_id(
        self: @TState,
        context_owner: starknet::ContractAddress,
        context_id: u64,
        prize_id: u64,
        position: u32,
    ) -> u256;

    fn is_position_claimed(
        self: @TState,
        context_owner: starknet::ContractAddress,
        context_id: u64,
        prize_id: u64,
        position: u32,
    ) -> bool;
}

#[starknet::contract]
pub mod nft_prize {
    use metagame_extensions_prize::prize_extension_component::PrizeExtensionComponent;
    use metagame_extensions_prize::prize_extension_component::PrizeExtensionComponent::PrizeExtension;
    use openzeppelin_interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::{ContractAddress, get_contract_address};
    use super::INFTPrize;

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
        prize_token_address: Map<(ContractAddress, u64, u64), ContractAddress>,
        prize_num_positions: Map<(ContractAddress, u64, u64), u32>,
        /// (context_owner, context_id, prize_id, 1-indexed position) -> token id
        prize_position_token_id: Map<(ContractAddress, u64, u64, u32), u256>,
        prize_position_claimed: Map<(ContractAddress, u64, u64, u32), bool>,
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

    #[abi(embed_v0)]
    impl NFTPrizeViewImpl of INFTPrize<ContractState> {
        fn get_token_address(
            self: @ContractState, context_owner: ContractAddress, context_id: u64, prize_id: u64,
        ) -> ContractAddress {
            self.prize_token_address.read((context_owner, context_id, prize_id))
        }

        fn get_position_token_id(
            self: @ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            prize_id: u64,
            position: u32,
        ) -> u256 {
            self.prize_position_token_id.read((context_owner, context_id, prize_id, position))
        }

        fn is_position_claimed(
            self: @ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            prize_id: u64,
            position: u32,
        ) -> bool {
            self.prize_position_claimed.read((context_owner, context_id, prize_id, position))
        }
    }

    impl NFTPrizeExtensionImpl of PrizeExtension<ContractState> {
        fn add_prize(
            ref self: ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            prize_id: u64,
            config: Span<felt252>,
        ) {
            // Minimum: [token, num_positions] (2) + at least 1 NFT (2)
            assert!(
                config.len() >= 4,
                "NFTPrize: config must be [token, num_positions, ...id_low_high pairs]",
            );
            let token: ContractAddress = (*config.at(0)).try_into().unwrap();
            let num_positions: u32 = (*config.at(1)).try_into().unwrap();
            assert!(num_positions > 0, "NFTPrize: num_positions must be > 0");
            assert!(
                config.len() == 2 + (num_positions * 2),
                "NFTPrize: config length must equal 2 + num_positions * 2",
            );

            let key = (context_owner, context_id, prize_id);
            assert!(self.prize_num_positions.read(key) == 0, "NFTPrize: prize already configured");
            self.prize_token_address.write(key, token);
            self.prize_num_positions.write(key, num_positions);

            let erc721 = IERC721Dispatcher { contract_address: token };
            let self_address = get_contract_address();
            let mut i: u32 = 0;
            while i < num_positions {
                let pair_base: u32 = 2 + (i * 2);
                let id_low: u128 = (*config.at(pair_base)).try_into().unwrap();
                let id_high: u128 = (*config.at(pair_base + 1)).try_into().unwrap();
                let token_id = u256 { low: id_low, high: id_high };
                let position = i + 1;
                self
                    .prize_position_token_id
                    .write((context_owner, context_id, prize_id, position), token_id);
                // Sanity: sponsor must have already transferred the NFT.
                assert!(
                    erc721.owner_of(token_id) == self_address,
                    "NFTPrize: token must be pre-transferred to extension",
                );
                i += 1;
            }
        }

        fn get_config(
            self: @ContractState, context_owner: ContractAddress, context_id: u64, prize_id: u64,
        ) -> Span<felt252> {
            // Re-serialize the stored fields back to the original
            // `[token_address, num_positions, id_0_lo, id_0_hi, ...]`
            // shape passed to add_prize. Returns an empty span for unknown
            // prizes (num_positions == 0 — add_prize asserts > 0 so
            // unambiguous).
            let key = (context_owner, context_id, prize_id);
            let num_positions = self.prize_num_positions.read(key);
            if num_positions == 0 {
                return array![].span();
            }
            let token = self.prize_token_address.read(key);
            let mut out: Array<felt252> = array![];
            out.append(token.into());
            out.append(num_positions.into());
            let mut i: u32 = 1;
            while i <= num_positions {
                let token_id = self
                    .prize_position_token_id
                    .read((context_owner, context_id, prize_id, i));
                out.append(token_id.low.into());
                out.append(token_id.high.into());
                i += 1;
            }
            out.span()
        }

        /// Transfer the NFT escrowed for `position` to `recipient`. The host
        /// (typically budokan) is responsible for picking the recipient —
        /// the leaderboard winner for a normal payout, or the original
        /// sponsor for a refund when no winner qualified at this position.
        /// This contract has no opinion about which case it is.
        ///
        /// `payout_params` is unused for NFTPrize. NFTPrize is positional
        /// — non-positional callers (`position == Option::None`) panic.
        fn payout_prize(
            ref self: ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            prize_id: u64,
            position: Option<u32>,
            recipient: ContractAddress,
            payout_params: Span<felt252>,
        ) {
            let _ = payout_params;
            let position = match position {
                Option::Some(p) => p,
                Option::None => panic!("NFTPrize: position is required"),
            };
            assert!(position > 0, "NFTPrize: position must be 1-indexed");

            let key = (context_owner, context_id, prize_id);
            let num_positions = self.prize_num_positions.read(key);
            assert!(num_positions > 0, "NFTPrize: prize not configured");
            assert!(position <= num_positions, "NFTPrize: position out of range");

            let claim_key = (context_owner, context_id, prize_id, position);
            assert!(
                !self.prize_position_claimed.read(claim_key), "NFTPrize: position already claimed",
            );

            self.prize_position_claimed.write(claim_key, true);

            let prize_token = self.prize_token_address.read(key);
            let prize_token_id = self.prize_position_token_id.read(claim_key);
            let erc721 = IERC721Dispatcher { contract_address: prize_token };
            erc721.transfer_from(get_contract_address(), recipient, prize_token_id);
        }
    }
}
