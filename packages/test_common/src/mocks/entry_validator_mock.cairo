use starknet::ContractAddress;

#[starknet::interface]
pub trait IEntryRequirementExtensionMock<TState> {
    fn get_context_erc721_address(self: @TState, context_id: u64) -> ContractAddress;
}

#[starknet::contract]
pub mod entry_validator_mock {
    use core::num::traits::Zero;
    use metagame_extensions_entry_requirement::entry_requirement_extension_component::EntryRequirementExtensionComponent;
    use metagame_extensions_entry_requirement::entry_requirement_extension_component::EntryRequirementExtensionComponent::EntryRequirementExtension;
    use openzeppelin_interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};

    component!(
        path: EntryRequirementExtensionComponent,
        storage: entry_validator,
        event: EntryValidatorEvent,
    );
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl EntryRequirementExtensionImpl =
        EntryRequirementExtensionComponent::EntryRequirementExtensionImpl<ContractState>;
    impl EntryRequirementExtensionInternalImpl =
        EntryRequirementExtensionComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        entry_validator: EntryRequirementExtensionComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        context_erc721_address: Map<u64, ContractAddress>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        EntryValidatorEvent: EntryRequirementExtensionComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        // ERC721 ownership can change, so allow banning (registration_only = false)
        self.entry_validator.initializer(false);
    }

    impl EntryRequirementExtensionImplInternal of EntryRequirementExtension<ContractState> {
        fn validate_entry(
            self: @ContractState,
            context_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            let erc721_address = self.context_erc721_address.read(context_id);

            // Check if ERC721 address is set for this context
            if erc721_address.is_zero() {
                return false;
            }

            let erc721 = IERC721Dispatcher { contract_address: erc721_address };

            // Check if the player owns at least one token
            let balance = erc721.balance_of(player_address);
            balance > 0
        }

        fn should_ban_entry(
            self: @ContractState,
            context_id: u64,
            game_token_id: felt252,
            current_owner: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            // Ban if player no longer owns the ERC721 token
            let erc721_address = self.context_erc721_address.read(context_id);
            if erc721_address.is_zero() {
                return false;
            }

            let erc721 = IERC721Dispatcher { contract_address: erc721_address };
            let balance = erc721.balance_of(current_owner);
            balance == 0
        }

        fn entries_left(
            self: @ContractState,
            context_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> Option<u32> {
            // For this mock, we assume unlimited entries
            Option::None
        }

        fn add_config(
            ref self: ContractState, context_id: u64, entry_limit: u32, config: Span<felt252>,
        ) {
            // Extract ERC721 address from config (first element)
            let erc721_address: ContractAddress = (*config.at(0)).try_into().unwrap();
            self.context_erc721_address.write(context_id, erc721_address);
        }

        fn on_entry_added(
            ref self: ContractState,
            context_id: u64,
            game_token_id: felt252,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) { // No specific action needed for this mock
        }

        fn on_entry_removed(
            ref self: ContractState,
            context_id: u64,
            game_token_id: felt252,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) { // No specific action needed for this mock
        }
    }

    // Public interface implementation
    use super::IEntryRequirementExtensionMock;
    #[abi(embed_v0)]
    impl EntryValidatorMockImpl of IEntryRequirementExtensionMock<ContractState> {
        fn get_context_erc721_address(self: @ContractState, context_id: u64) -> ContractAddress {
            self.context_erc721_address.read(context_id)
        }
    }
}
