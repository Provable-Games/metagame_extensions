/// EntryRequirementExtensionComponent provides extensible entry validation for any context.
/// This component allows external contracts to implement custom entry validation logic.

#[starknet::component]
pub mod EntryRequirementExtensionComponent {
    use metagame_extensions_interfaces::entry_requirement_extension::{
        IENTRY_REQUIREMENT_EXTENSION_ID, IEntryRequirementExtension,
        LEGACY_IENTRY_REQUIREMENT_EXTENSION_ID_V3, LEGACY_IENTRY_VALIDATOR_ID_V1,
        LEGACY_IENTRY_VALIDATOR_ID_V2,
    };
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_introspection::src5::SRC5Component::InternalTrait as SRC5InternalTrait;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};

    #[storage]
    pub struct Storage {
        context_owner: Map<u64, ContractAddress>,
        registration_only: bool,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {}

    /// Internal trait that implementors must provide.
    /// This trait defines the validation logic that each extension implements.
    pub trait EntryRequirementExtension<TContractState> {
        /// Validate if a player can enter a context (for NEW entries)
        fn validate_entry(
            self: @TContractState,
            context_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool;

        /// Determine if an existing entry should be banned (for EXISTING entries)
        /// Returns true if the entry should be banned
        fn should_ban_entry(
            self: @TContractState,
            context_id: u64,
            game_token_id: felt252,
            current_owner: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool;

        /// Check how many entries are left for a player
        fn entries_left(
            self: @TContractState,
            context_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> Option<u8>;

        /// Add configuration for a context
        fn add_config(
            ref self: TContractState, context_id: u64, entry_limit: u8, config: Span<felt252>,
        );

        /// Called when an entry is added
        fn on_entry_added(
            ref self: TContractState,
            context_id: u64,
            game_token_id: felt252,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        );

        /// Called when an entry is removed (banned)
        fn on_entry_removed(
            ref self: TContractState,
            context_id: u64,
            game_token_id: felt252,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        );
    }

    #[embeddable_as(EntryRequirementExtensionImpl)]
    impl EntryRequirementExtensionComponentImpl<
        TContractState,
        +HasComponent<TContractState>,
        +EntryRequirementExtension<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        +Drop<TContractState>,
    > of IEntryRequirementExtension<ComponentState<TContractState>> {
        fn context_owner(
            self: @ComponentState<TContractState>, context_id: u64,
        ) -> ContractAddress {
            self.context_owner.read(context_id)
        }

        fn registration_only(self: @ComponentState<TContractState>) -> bool {
            self.registration_only.read()
        }

        fn valid_entry(
            self: @ComponentState<TContractState>,
            context_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            let contract = self.get_contract();
            EntryRequirementExtension::validate_entry(
                contract, context_id, player_address, qualification,
            )
        }

        fn should_ban(
            self: @ComponentState<TContractState>,
            context_id: u64,
            game_token_id: felt252,
            current_owner: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            let contract = self.get_contract();
            EntryRequirementExtension::should_ban_entry(
                contract, context_id, game_token_id, current_owner, qualification,
            )
        }

        fn entries_left(
            self: @ComponentState<TContractState>,
            context_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> Option<u8> {
            let contract = self.get_contract();
            EntryRequirementExtension::entries_left(
                contract, context_id, player_address, qualification,
            )
        }

        fn add_config(
            ref self: ComponentState<TContractState>,
            context_id: u64,
            entry_limit: u8,
            config: Span<felt252>,
        ) {
            self.set_context_owner(context_id);
            let mut contract = self.get_contract_mut();
            EntryRequirementExtension::add_config(ref contract, context_id, entry_limit, config);
        }

        fn add_entry(
            ref self: ComponentState<TContractState>,
            context_id: u64,
            game_token_id: felt252,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) {
            self.assert_context_owner(context_id);
            let mut contract = self.get_contract_mut();
            EntryRequirementExtension::on_entry_added(
                ref contract, context_id, game_token_id, player_address, qualification,
            );
        }

        fn remove_entry(
            ref self: ComponentState<TContractState>,
            context_id: u64,
            game_token_id: felt252,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) {
            self.assert_context_owner(context_id);
            let mut contract = self.get_contract_mut();
            EntryRequirementExtension::on_entry_removed(
                ref contract, context_id, game_token_id, player_address, qualification,
            );
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState,
        +HasComponent<TContractState>,
        impl SRC5: SRC5Component::HasComponent<TContractState>,
        +Drop<TContractState>,
    > of InternalTrait<TContractState> {
        fn initializer(ref self: ComponentState<TContractState>, registration_only: bool) {
            self.registration_only.write(registration_only);

            let mut src5_component = get_dep_component_mut!(ref self, SRC5);
            src5_component.register_interface(IENTRY_REQUIREMENT_EXTENSION_ID);
            src5_component.register_interface(LEGACY_IENTRY_REQUIREMENT_EXTENSION_ID_V3);
            src5_component.register_interface(LEGACY_IENTRY_VALIDATOR_ID_V2);
            src5_component.register_interface(LEGACY_IENTRY_VALIDATOR_ID_V1);
        }

        fn get_context_owner(
            self: @ComponentState<TContractState>, context_id: u64,
        ) -> ContractAddress {
            self.context_owner.read(context_id)
        }

        fn is_registration_only(self: @ComponentState<TContractState>) -> bool {
            self.registration_only.read()
        }

        fn set_context_owner(ref self: ComponentState<TContractState>, context_id: u64) {
            let caller = get_caller_address();
            let current_owner = self.context_owner.read(context_id);
            let zero: ContractAddress = 0.try_into().unwrap();
            if current_owner == zero {
                self.context_owner.write(context_id, caller);
            } else {
                assert!(
                    caller == current_owner,
                    "Entry Requirement Extension: Only context owner can call",
                );
            }
        }

        fn assert_context_owner(self: @ComponentState<TContractState>, context_id: u64) {
            let caller = get_caller_address();
            let current_owner = self.context_owner.read(context_id);
            let zero: ContractAddress = 0.try_into().unwrap();
            assert!(current_owner != zero, "Entry Requirement Extension: Context has no owner");
            assert!(
                caller == current_owner, "Entry Requirement Extension: Only context owner can call",
            );
        }
    }
}
