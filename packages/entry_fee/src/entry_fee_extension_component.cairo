/// EntryFeeExtensionComponent provides extensible entry fee logic for any context.
/// This component allows external contracts to implement custom entry fee setup,
/// payment, and claim hooks.

#[starknet::component]
pub mod EntryFeeExtensionComponent {
    use metagame_extensions_interfaces::entry_fee_extension::{
        IENTRY_FEE_EXTENSION_ID, IEntryFeeExtension, LEGACY_IENTRY_FEE_EXTENSION_ID,
    };
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_introspection::src5::SRC5Component::InternalTrait as SRC5InternalTrait;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use starknet::{ContractAddress, get_caller_address};

    #[storage]
    pub struct Storage {
        context_owner: Map<u64, ContractAddress>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {}

    /// Internal trait that implementors must provide.
    /// This trait defines the fee logic that each extension implements.
    pub trait EntryFeeExtension<TContractState> {
        /// Set entry fee configuration for a context (called during setup)
        fn set_entry_fee_config(ref self: TContractState, context_id: u64, config: Span<felt252>);

        /// Pay entry fee for a context (called during deposit via extension)
        fn pay_entry_fee(ref self: TContractState, context_id: u64, pay_params: Span<felt252>);

        /// Claim entry fee for a context
        fn claim_entry_fee(ref self: TContractState, context_id: u64, claim_params: Span<felt252>);
    }

    #[embeddable_as(EntryFeeExtensionImpl)]
    impl EntryFeeExtensionComponentImpl<
        TContractState,
        +HasComponent<TContractState>,
        +EntryFeeExtension<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        +Drop<TContractState>,
    > of IEntryFeeExtension<ComponentState<TContractState>> {
        fn context_owner(
            self: @ComponentState<TContractState>, context_id: u64,
        ) -> ContractAddress {
            self.context_owner.read(context_id)
        }

        fn set_entry_fee_config(
            ref self: ComponentState<TContractState>, context_id: u64, config: Span<felt252>,
        ) {
            self.set_context_owner(context_id);
            let mut contract = self.get_contract_mut();
            EntryFeeExtension::set_entry_fee_config(ref contract, context_id, config);
        }

        fn pay_entry_fee(
            ref self: ComponentState<TContractState>, context_id: u64, pay_params: Span<felt252>,
        ) {
            self.assert_context_owner(context_id);
            let mut contract = self.get_contract_mut();
            EntryFeeExtension::pay_entry_fee(ref contract, context_id, pay_params);
        }

        fn claim_entry_fee(
            ref self: ComponentState<TContractState>, context_id: u64, claim_params: Span<felt252>,
        ) {
            self.assert_context_owner(context_id);
            let mut contract = self.get_contract_mut();
            EntryFeeExtension::claim_entry_fee(ref contract, context_id, claim_params);
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
            src5_component.register_interface(LEGACY_IENTRY_FEE_EXTENSION_ID);
        }

        fn set_context_owner(ref self: ComponentState<TContractState>, context_id: u64) {
            let caller = get_caller_address();
            let current_owner = self.context_owner.read(context_id);
            let zero: ContractAddress = 0.try_into().unwrap();
            if current_owner == zero {
                self.context_owner.write(context_id, caller);
            } else {
                assert!(
                    caller == current_owner, "Entry Fee Extension: Only context owner can call",
                );
            }
        }

        fn assert_context_owner(self: @ComponentState<TContractState>, context_id: u64) {
            let caller = get_caller_address();
            let current_owner = self.context_owner.read(context_id);
            let zero: ContractAddress = 0.try_into().unwrap();
            assert!(current_owner != zero, "Entry Fee Extension: Context has no owner");
            assert!(caller == current_owner, "Entry Fee Extension: Only context owner can call");
        }
    }
}
