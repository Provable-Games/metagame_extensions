/// PrizeExtensionComponent provides extensible prize logic for any context.
/// This component allows external contracts to implement custom prize addition
/// and claim hooks.

#[starknet::component]
pub mod PrizeExtensionComponent {
    use metagame_extensions_interfaces::prize_extension::{
        IPRIZE_EXTENSION_ID, IPrizeExtension, LEGACY_IPRIZE_EXTENSION_ID,
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
    /// This trait defines the prize logic that each extension implements.
    pub trait PrizeExtension<TContractState> {
        /// Add a prize configuration for a context
        fn add_prize(
            ref self: TContractState, context_id: u64, prize_id: u64, config: Span<felt252>,
        );

        /// Claim a prize for a context
        fn claim_prize(ref self: TContractState, context_id: u64, claim_params: Span<felt252>);
    }

    #[embeddable_as(PrizeExtensionImpl)]
    impl PrizeExtensionComponentImpl<
        TContractState,
        +HasComponent<TContractState>,
        +PrizeExtension<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        +Drop<TContractState>,
    > of IPrizeExtension<ComponentState<TContractState>> {
        fn context_owner(
            self: @ComponentState<TContractState>, context_id: u64,
        ) -> ContractAddress {
            self.context_owner.read(context_id)
        }

        fn add_prize(
            ref self: ComponentState<TContractState>,
            context_id: u64,
            prize_id: u64,
            config: Span<felt252>,
        ) {
            self.set_context_owner(context_id);
            let mut contract = self.get_contract_mut();
            PrizeExtension::add_prize(ref contract, context_id, prize_id, config);
        }

        fn claim_prize(
            ref self: ComponentState<TContractState>, context_id: u64, claim_params: Span<felt252>,
        ) {
            self.assert_context_owner(context_id);
            let mut contract = self.get_contract_mut();
            PrizeExtension::claim_prize(ref contract, context_id, claim_params);
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
            src5_component.register_interface(IPRIZE_EXTENSION_ID);
            src5_component.register_interface(LEGACY_IPRIZE_EXTENSION_ID);
        }

        fn set_context_owner(ref self: ComponentState<TContractState>, context_id: u64) {
            let caller = get_caller_address();
            let current_owner = self.context_owner.read(context_id);
            let zero: ContractAddress = 0.try_into().unwrap();
            if current_owner == zero {
                self.context_owner.write(context_id, caller);
            } else {
                assert!(caller == current_owner, "Prize Extension: Only context owner can call");
            }
        }

        fn assert_context_owner(self: @ComponentState<TContractState>, context_id: u64) {
            let caller = get_caller_address();
            let current_owner = self.context_owner.read(context_id);
            let zero: ContractAddress = 0.try_into().unwrap();
            assert!(current_owner != zero, "Prize Extension: Context has no owner");
            assert!(caller == current_owner, "Prize Extension: Only context owner can call");
        }
    }
}
