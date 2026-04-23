/// EntryRequirementExtensionComponent provides extensible entry validation for any context.
/// This component allows external contracts to implement custom entry validation logic.
///
/// Storage is namespaced by `(context_owner, context_id)`. The `context_owner` is
/// the contract address that first calls `add_config` for a given `context_id`.
/// Re-registration from the same owner reverts; different owners can use the same
/// `context_id` independently on the same validator contract.

#[starknet::component]
pub mod EntryRequirementExtensionComponent {
    use metagame_extensions_interfaces::entry_requirement_extension::{
        IENTRY_REQUIREMENT_EXTENSION_ID, IEntryRequirementExtension,
    };
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_introspection::src5::SRC5Component::InternalTrait as SRC5InternalTrait;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::{ContractAddress, get_caller_address};

    #[storage]
    pub struct Storage {
        context_registered: Map<(ContractAddress, u64), bool>,
        bannable: Map<(ContractAddress, u64), bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {}

    /// Internal trait that implementors must provide.
    /// `context_owner` is the namespace under which per-context state lives.
    pub trait EntryRequirementExtension<TContractState> {
        /// Validate if a player can enter a context (for NEW entries)
        fn validate_entry(
            self: @TContractState,
            context_owner: ContractAddress,
            context_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool;

        /// Determine if an existing entry should be banned (for EXISTING entries).
        /// Returns true if the entry should be banned.
        fn should_ban_entry(
            self: @TContractState,
            context_owner: ContractAddress,
            context_id: u64,
            game_token_id: felt252,
            current_owner: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool;

        /// Check how many entries are left for a player
        fn entries_left(
            self: @TContractState,
            context_owner: ContractAddress,
            context_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> Option<u32>;

        /// Register configuration under `(context_owner, context_id)`.
        fn add_config(
            ref self: TContractState,
            context_owner: ContractAddress,
            context_id: u64,
            entry_limit: u32,
            config: Span<felt252>,
        );

        /// Called when an entry is added
        fn on_entry_added(
            ref self: TContractState,
            context_owner: ContractAddress,
            context_id: u64,
            game_token_id: felt252,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        );

        /// Called when an entry is removed (banned)
        fn on_entry_removed(
            ref self: TContractState,
            context_owner: ContractAddress,
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
        fn is_context_registered(
            self: @ComponentState<TContractState>, context_owner: ContractAddress, context_id: u64,
        ) -> bool {
            self.context_registered.read((context_owner, context_id))
        }

        fn bannable(
            self: @ComponentState<TContractState>, context_owner: ContractAddress, context_id: u64,
        ) -> bool {
            self.bannable.read((context_owner, context_id))
        }

        fn valid_entry(
            self: @ComponentState<TContractState>,
            context_owner: ContractAddress,
            context_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            let contract = self.get_contract();
            EntryRequirementExtension::validate_entry(
                contract, context_owner, context_id, player_address, qualification,
            )
        }

        fn should_ban(
            self: @ComponentState<TContractState>,
            context_owner: ContractAddress,
            context_id: u64,
            game_token_id: felt252,
            current_owner: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            if !self.bannable.read((context_owner, context_id)) {
                return false;
            }
            let contract = self.get_contract();
            EntryRequirementExtension::should_ban_entry(
                contract, context_owner, context_id, game_token_id, current_owner, qualification,
            )
        }

        fn entries_left(
            self: @ComponentState<TContractState>,
            context_owner: ContractAddress,
            context_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> Option<u32> {
            let contract = self.get_contract();
            EntryRequirementExtension::entries_left(
                contract, context_owner, context_id, player_address, qualification,
            )
        }

        fn add_config(
            ref self: ComponentState<TContractState>,
            context_id: u64,
            entry_limit: u32,
            config: Span<felt252>,
        ) {
            let caller = get_caller_address();
            self.register_context(caller, context_id);
            let mut contract = self.get_contract_mut();
            EntryRequirementExtension::add_config(
                ref contract, caller, context_id, entry_limit, config,
            );
        }

        fn add_entry(
            ref self: ComponentState<TContractState>,
            context_id: u64,
            game_token_id: felt252,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) {
            let caller = get_caller_address();
            self.assert_registered(caller, context_id);
            let mut contract = self.get_contract_mut();
            EntryRequirementExtension::on_entry_added(
                ref contract, caller, context_id, game_token_id, player_address, qualification,
            );
        }

        fn remove_entry(
            ref self: ComponentState<TContractState>,
            context_id: u64,
            game_token_id: felt252,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) {
            let caller = get_caller_address();
            self.assert_registered(caller, context_id);
            let mut contract = self.get_contract_mut();
            EntryRequirementExtension::on_entry_removed(
                ref contract, caller, context_id, game_token_id, player_address, qualification,
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
        fn initializer(ref self: ComponentState<TContractState>) {
            let mut src5_component = get_dep_component_mut!(ref self, SRC5);
            src5_component.register_interface(IENTRY_REQUIREMENT_EXTENSION_ID);
        }

        fn is_registered(
            self: @ComponentState<TContractState>, context_owner: ContractAddress, context_id: u64,
        ) -> bool {
            self.context_registered.read((context_owner, context_id))
        }

        fn is_bannable(
            self: @ComponentState<TContractState>, context_owner: ContractAddress, context_id: u64,
        ) -> bool {
            self.bannable.read((context_owner, context_id))
        }

        fn set_bannable(
            ref self: ComponentState<TContractState>,
            context_owner: ContractAddress,
            context_id: u64,
            bannable: bool,
        ) {
            self.bannable.write((context_owner, context_id), bannable);
        }

        /// Register `(context_owner, context_id)` — reverts if already registered.
        fn register_context(
            ref self: ComponentState<TContractState>,
            context_owner: ContractAddress,
            context_id: u64,
        ) {
            assert!(
                !self.context_registered.read((context_owner, context_id)),
                "Entry Requirement Extension: Context already registered",
            );
            self.context_registered.write((context_owner, context_id), true);
        }

        /// Assert `(context_owner, context_id)` has been registered.
        fn assert_registered(
            self: @ComponentState<TContractState>, context_owner: ContractAddress, context_id: u64,
        ) {
            assert!(
                self.context_registered.read((context_owner, context_id)),
                "Entry Requirement Extension: Context not registered",
            );
        }
    }
}
