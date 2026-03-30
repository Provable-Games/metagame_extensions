#[starknet::contract]
pub mod open_entry_validator_mock {
    use metagame_extensions_entry_requirement::entry_requirement_extension_component::EntryRequirementExtensionComponent;
    use metagame_extensions_entry_requirement::entry_requirement_extension_component::EntryRequirementExtensionComponent::EntryRequirementExtension;
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
        tournament_entry_limit: Map<u64, u8>,
        tournament_entries: Map<(u64, ContractAddress), u8>,
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
        // Open validator: once registered, entry is always valid (registration_only = true)
        self.entry_validator.initializer(true);
    }

    impl EntryRequirementExtensionImplInternal of EntryRequirementExtension<ContractState> {
        fn validate_entry(
            self: @ContractState,
            context_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            // Open validator: everyone can enter regardless of tournament
            true
        }

        fn should_ban_entry(
            self: @ContractState,
            context_id: u64,
            game_token_id: felt252,
            current_owner: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            // Never ban open entries
            false
        }

        fn entries_left(
            self: @ContractState,
            context_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> Option<u8> {
            let entry_limit = self.tournament_entry_limit.read(context_id);
            if entry_limit == 0 {
                return Option::None; // Unlimited entries
            }
            let key = (context_id, player_address);
            let current_entries = self.tournament_entries.read(key);
            let remaining_entries = entry_limit - current_entries;
            return Option::Some(remaining_entries);
        }

        fn add_config(
            ref self: ContractState, context_id: u64, entry_limit: u8, config: Span<felt252>,
        ) {
            self.tournament_entry_limit.write(context_id, entry_limit);
        }

        fn on_entry_added(
            ref self: ContractState,
            context_id: u64,
            game_token_id: felt252,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) {
            let key = (context_id, player_address);
            let current_entries = self.tournament_entries.read(key);
            self.tournament_entries.write(key, current_entries + 1);
        }

        fn on_entry_removed(
            ref self: ContractState,
            context_id: u64,
            game_token_id: felt252,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) {
            let key = (context_id, player_address);
            let current_entries = self.tournament_entries.read(key);
            if current_entries > 0 {
                self.tournament_entries.write(key, current_entries - 1);
            }
        }
    }
}
