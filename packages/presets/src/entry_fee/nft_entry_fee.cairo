// SPDX-License-Identifier: BUSL-1.1

/// NFTEntryFee — entry requires transferring a specific ERC721 collection's
/// NFT into the extension's escrow. On finalization the tournament host
/// distributes the escrowed NFTs (e.g. to the winner, the creator, or
/// burnable to a dead address) by calling `claim_entry_fee` once per NFT.
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
/// 3. After finalization, drive `claim_entry_fee` per-index for each NFT in
///    the escrow. Claim params = `[recipient, index]` (0-indexed).

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

    fn is_claimed(
        self: @TState, context_owner: starknet::ContractAddress, context_id: u64, index: u32,
    ) -> bool;
}

#[starknet::contract]
pub mod nft_entry_fee {
    use metagame_extensions_entry_fee::entry_fee_extension_component::EntryFeeExtensionComponent;
    use metagame_extensions_entry_fee::entry_fee_extension_component::EntryFeeExtensionComponent::EntryFeeExtension;
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
            self.escrowed_count.write((context_owner, context_id), index + 1);
        }

        /// NFTEntryFee distributes one escrowed NFT per leaderboard
        /// position. The host computes recipient (winner or sponsor)
        /// and supplies `position` as Some(N) — `position - 1` indexes
        /// into the escrowed NFTs in deposit order. `claim_params` is
        /// unused.
        fn payout_entry_fee(
            ref self: ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            recipient: ContractAddress,
            position: Option<u32>,
            claim_params: Span<felt252>,
        ) {
            let _ = claim_params;
            let position = match position {
                Option::Some(p) => p,
                Option::None => panic!("NFTEntryFee: position is required"),
            };
            assert!(position > 0, "NFTEntryFee: position must be 1-indexed");
            let index: u32 = position - 1;

            let count = self.escrowed_count.read((context_owner, context_id));
            assert!(index < count, "NFTEntryFee: index out of range");
            let claim_key = (context_owner, context_id, index);
            assert!(!self.claimed.read(claim_key), "NFTEntryFee: already claimed");

            self.claimed.write(claim_key, true);
            let collection = self.collection.read((context_owner, context_id));
            let token_id = self.escrowed_token_id.read(claim_key);
            let erc721 = IERC721Dispatcher { contract_address: collection };
            erc721.transfer_from(get_contract_address(), recipient, token_id);
        }
    }
}
