/// EntryFeeExtensionComponent provides extensible entry fee logic for any context.
/// This component allows external contracts to implement custom entry fee setup,
/// payment, and claim hooks.
///
/// Storage is namespaced by `(context_owner, context_id)`. The `context_owner` is
/// the contract address that first calls `set_entry_fee_config` for a given
/// `context_id`. Re-registration from the same owner reverts.

#[starknet::component]
pub mod EntryFeeExtensionComponent {
    use metagame_extensions_interfaces::entry_fee_extension::{
        IENTRY_FEE_EXTENSION_ID, IEntryFeeExtension,
    };
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_introspection::src5::SRC5Component::InternalTrait as SRC5InternalTrait;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::{ContractAddress, get_caller_address};

    #[storage]
    pub struct Storage {
        context_registered: Map<(ContractAddress, u64), bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {}

    /// Internal trait that implementors must provide.
    /// `context_owner` is the namespace under which per-context state lives.
    pub trait EntryFeeExtension<TContractState> {
        /// Set entry fee configuration under `(context_owner, context_id)` (called during setup)
        fn set_entry_fee_config(
            ref self: TContractState,
            context_owner: ContractAddress,
            context_id: u64,
            config: Span<felt252>,
        );

        /// Pay entry fee for a context (called during deposit via extension)
        fn pay_entry_fee(
            ref self: TContractState,
            context_owner: ContractAddress,
            context_id: u64,
            pay_params: Span<felt252>,
        );

        /// Claim entry fee for a context
        fn claim_entry_fee(
            ref self: TContractState,
            context_owner: ContractAddress,
            context_id: u64,
            claim_params: Span<felt252>,
        );
    }

    #[embeddable_as(EntryFeeExtensionImpl)]
    impl EntryFeeExtensionComponentImpl<
        TContractState,
        +HasComponent<TContractState>,
        +EntryFeeExtension<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        +Drop<TContractState>,
    > of IEntryFeeExtension<ComponentState<TContractState>> {
        fn is_context_registered(
            self: @ComponentState<TContractState>, context_owner: ContractAddress, context_id: u64,
        ) -> bool {
            self.context_registered.read((context_owner, context_id))
        }

        fn set_entry_fee_config(
            ref self: ComponentState<TContractState>, context_id: u64, config: Span<felt252>,
        ) {
            let caller = get_caller_address();
            self.register_context(caller, context_id);
            let mut contract = self.get_contract_mut();
            EntryFeeExtension::set_entry_fee_config(ref contract, caller, context_id, config);
        }

        fn pay_entry_fee(
            ref self: ComponentState<TContractState>, context_id: u64, pay_params: Span<felt252>,
        ) {
            let caller = get_caller_address();
            self.assert_registered(caller, context_id);
            let mut contract = self.get_contract_mut();
            EntryFeeExtension::pay_entry_fee(ref contract, caller, context_id, pay_params);
        }

        fn claim_entry_fee(
            ref self: ComponentState<TContractState>, context_id: u64, claim_params: Span<felt252>,
        ) {
            let caller = get_caller_address();
            self.assert_registered(caller, context_id);
            let mut contract = self.get_contract_mut();
            EntryFeeExtension::claim_entry_fee(ref contract, caller, context_id, claim_params);
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
            src5_component.register_interface(IENTRY_FEE_EXTENSION_ID);
        }

        fn is_registered(
            self: @ComponentState<TContractState>, context_owner: ContractAddress, context_id: u64,
        ) -> bool {
            self.context_registered.read((context_owner, context_id))
        }

        /// Register `(context_owner, context_id)` — reverts if already registered.
        fn register_context(
            ref self: ComponentState<TContractState>,
            context_owner: ContractAddress,
            context_id: u64,
        ) {
            assert!(
                !self.context_registered.read((context_owner, context_id)),
                "Entry Fee Extension: Context already registered",
            );
            self.context_registered.write((context_owner, context_id), true);
        }

        /// Assert `(context_owner, context_id)` has been registered.
        fn assert_registered(
            self: @ComponentState<TContractState>, context_owner: ContractAddress, context_id: u64,
        ) {
            assert!(
                self.context_registered.read((context_owner, context_id)),
                "Entry Fee Extension: Context not registered",
            );
        }
    }
}
