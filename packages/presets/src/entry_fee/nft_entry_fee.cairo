// SPDX-License-Identifier: BUSL-1.1

/// NFTEntryFee — entry requires transferring a specific ERC721 collection's
/// NFT into the extension's escrow. On finalization the host distributes
/// the escrowed NFTs by leaderboard position. The extension is fully
/// sovereign: the host dispatches with a `token_id` (or `None` for refunds)
/// and NFTEntryFee resolves the position and recipient from its own state +
/// the host's `ILeaderboard`.
///
/// Demonstrates that the extension framework is not tied to fungible fees:
/// a "fee pool" can be a heterogeneous bag of NFTs, indexed by the order
/// in which players entered.
///
/// Player responsibilities
/// -----------------------
/// 1. Approve this contract for the specific token IDs they plan to enter with.
///
/// Host responsibilities
/// ---------------------
/// 1. Set up with config = `[nft_collection_address]`.
/// 2. Forward `pay_entry_fee` with pay_params = `[payer, token_id_low, token_id_high]`.
///    The payer is tracked per-index for the refund branch.
/// 3. After finalization, drive `payout_entry_fee` per-claim:
///    - Claim: `token_id = Some(game_token)`, `claim_params = []`. Extension
///      derives position via `ILeaderboard::get_position`, recipient as
///      `owner_of(game_token)`, and transfers escrow slot `position - 1`.
///    - Refund: `token_id = None`, `claim_params = [slot_index]`. Extension
///      verifies `slot_index > leaderboard_length` and refunds escrow slot
///      `slot_index - 1` to its original payer.

#[starknet::interface]
pub trait INFTEntryFee<TState> {
    fn get_collection(
        self: @TState, context_owner: starknet::ContractAddress, context_id: u64,
    ) -> starknet::ContractAddress;

    fn get_escrowed_count(
        self: @TState, context_owner: starknet::ContractAddress, context_id: u64,
    ) -> u32;

    fn get_escrowed_token_id(
        self: @TState, context_owner: starknet::ContractAddress, context_id: u64, index: u32,
    ) -> u256;

    fn get_escrowed_payer(
        self: @TState, context_owner: starknet::ContractAddress, context_id: u64, index: u32,
    ) -> starknet::ContractAddress;

    fn is_claimed(
        self: @TState, context_owner: starknet::ContractAddress, context_id: u64, index: u32,
    ) -> bool;
}

#[starknet::contract]
pub mod nft_entry_fee {
    use core::num::traits::Zero;
    use metagame_extensions_entry_fee::entry_fee_extension_component::EntryFeeExtensionComponent;
    use metagame_extensions_entry_fee::entry_fee_extension_component::EntryFeeExtensionComponent::EntryFeeExtension;
    use metagame_extensions_presets::externals::game_components::{
        ILeaderboardDispatcher, ILeaderboardDispatcherTrait, IMinigameDispatcher,
        IMinigameDispatcherTrait,
    };
    use openzeppelin_interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::{ContractAddress, get_contract_address};
    use super::INFTEntryFee;

    component!(path: EntryFeeExtensionComponent, storage: entry_fee, event: EntryFeeEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl EntryFeeExtensionImpl =
        EntryFeeExtensionComponent::EntryFeeExtensionImpl<ContractState>;
    impl EntryFeeExtensionInternalImpl = EntryFeeExtensionComponent::InternalImpl<ContractState>;
    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        entry_fee: EntryFeeExtensionComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        collection: Map<(ContractAddress, u64), ContractAddress>,
        escrowed_count: Map<(ContractAddress, u64), u32>,
        /// (context_owner, context_id, 0-indexed slot) -> token id
        escrowed_token_id: Map<(ContractAddress, u64, u32), u256>,
        /// (context_owner, context_id, 0-indexed slot) -> original payer
        /// Used for the refund branch when position > leaderboard length.
        escrowed_payer: Map<(ContractAddress, u64, u32), ContractAddress>,
        claimed: Map<(ContractAddress, u64, u32), bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        EntryFeeEvent: EntryFeeExtensionComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.entry_fee.initializer();
    }

    #[abi(embed_v0)]
    impl NFTEntryFeeViewImpl of INFTEntryFee<ContractState> {
        fn get_collection(
            self: @ContractState, context_owner: ContractAddress, context_id: u64,
        ) -> ContractAddress {
            self.collection.read((context_owner, context_id))
        }

        fn get_escrowed_count(
            self: @ContractState, context_owner: ContractAddress, context_id: u64,
        ) -> u32 {
            self.escrowed_count.read((context_owner, context_id))
        }

        fn get_escrowed_token_id(
            self: @ContractState, context_owner: ContractAddress, context_id: u64, index: u32,
        ) -> u256 {
            self.escrowed_token_id.read((context_owner, context_id, index))
        }

        fn get_escrowed_payer(
            self: @ContractState, context_owner: ContractAddress, context_id: u64, index: u32,
        ) -> ContractAddress {
            self.escrowed_payer.read((context_owner, context_id, index))
        }

        fn is_claimed(
            self: @ContractState, context_owner: ContractAddress, context_id: u64, index: u32,
        ) -> bool {
            self.claimed.read((context_owner, context_id, index))
        }
    }

    impl NFTEntryFeeExtensionImpl of EntryFeeExtension<ContractState> {
        fn set_entry_fee_config(
            ref self: ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            config: Span<felt252>,
        ) {
            assert!(config.len() == 1, "NFTEntryFee: config must be [collection_address]");
            let collection: ContractAddress = (*config.at(0)).try_into().unwrap();
            self.collection.write((context_owner, context_id), collection);
        }

        fn pay_entry_fee(
            ref self: ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            pay_params: Span<felt252>,
        ) {
            assert!(
                pay_params.len() == 3,
                "NFTEntryFee: pay_params must be [payer, token_id_low, token_id_high]",
            );
            let payer: ContractAddress = (*pay_params.at(0)).try_into().unwrap();
            let id_low: u128 = (*pay_params.at(1)).try_into().unwrap();
            let id_high: u128 = (*pay_params.at(2)).try_into().unwrap();
            let token_id = u256 { low: id_low, high: id_high };

            let collection = self.collection.read((context_owner, context_id));
            let erc721 = IERC721Dispatcher { contract_address: collection };
            erc721.transfer_from(payer, get_contract_address(), token_id);

            let index = self.escrowed_count.read((context_owner, context_id));
            self.escrowed_token_id.write((context_owner, context_id, index), token_id);
            self.escrowed_payer.write((context_owner, context_id, index), payer);
            self.escrowed_count.write((context_owner, context_id), index + 1);
        }

        /// Re-serialize the stored config back to the
        /// `[collection_address]` shape passed to set_entry_fee_config.
        /// Returns an empty span when the context tuple is unknown
        /// (collection unset).
        fn get_config(
            self: @ContractState, context_owner: ContractAddress, context_id: u64,
        ) -> Span<felt252> {
            let collection = self.collection.read((context_owner, context_id));
            if collection.is_zero() {
                return array![].span();
            }
            array![collection.into()].span()
        }

        /// Dispatch a fee-pool NFT payout.
        ///
        /// Claim path (`token_id = Some(game_token)`):
        /// - Look up the token's leaderboard position via
        ///   `ILeaderboard::get_position`. Reverts if the token is not on
        ///   the leaderboard. Position 1 maps to escrow slot 0, position 2
        ///   to slot 1, etc.
        /// - Derive recipient as `owner_of(game_token)`.
        /// - Transfer the escrowed NFT at slot `position - 1`.
        ///
        /// Refund path (`token_id = None`, `claim_params = [slot_index]`):
        /// - `slot_index` must be 1-indexed and within
        ///   `1..=escrowed_count`. Reverts if `slot_index <= leaderboard_length`
        ///   (a qualifying winner exists for that slot — claim path applies).
        /// - Refund the escrowed NFT at slot `slot_index - 1` to its
        ///   original payer.
        fn payout_entry_fee(
            ref self: ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            token_id: Option<felt252>,
            claim_params: Span<felt252>,
        ) {
            let count = self.escrowed_count.read((context_owner, context_id));
            let leaderboard = ILeaderboardDispatcher { contract_address: context_owner };

            let (position, recipient): (u32, ContractAddress) = match token_id {
                Option::Some(claimant_token) => {
                    let position = match leaderboard.get_position(context_id, claimant_token) {
                        Option::Some(p) => p,
                        Option::None => panic!("NFTEntryFee: token not on leaderboard"),
                    };
                    assert!(position <= count, "NFTEntryFee: position out of escrow range");

                    let game_token_address = IMinigameDispatcher { contract_address: context_owner }
                        .token_address();
                    let game_token = IERC721Dispatcher { contract_address: game_token_address };
                    let claimant_token_u256: u256 = claimant_token.into();
                    let owner = game_token.owner_of(claimant_token_u256);
                    (position, owner)
                },
                Option::None => {
                    assert!(
                        claim_params.len() == 1,
                        "NFTEntryFee: refund requires claim_params = [slot_index]",
                    );
                    let slot_index: u32 = (*claim_params.at(0)).try_into().unwrap();
                    assert!(slot_index > 0, "NFTEntryFee: slot_index must be 1-indexed");
                    assert!(slot_index <= count, "NFTEntryFee: slot_index out of escrow range");

                    let length = leaderboard.get_leaderboard_length(context_id);
                    assert!(
                        slot_index > length,
                        "NFTEntryFee: slot has a qualifying winner; use the claim path",
                    );

                    // Refund to original payer of this escrow slot.
                    let index: u32 = slot_index - 1;
                    let payer = self.escrowed_payer.read((context_owner, context_id, index));
                    (slot_index, payer)
                },
            };

            let index: u32 = position - 1;
            let claim_key = (context_owner, context_id, index);
            assert!(!self.claimed.read(claim_key), "NFTEntryFee: already claimed");
            self.claimed.write(claim_key, true);

            let collection = self.collection.read((context_owner, context_id));
            let stored_token_id = self.escrowed_token_id.read(claim_key);
            let erc721 = IERC721Dispatcher { contract_address: collection };
            erc721.transfer_from(get_contract_address(), recipient, stored_token_id);
        }
    }
}
