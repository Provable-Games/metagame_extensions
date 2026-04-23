/// PrizeExtensionComponent provides extensible prize logic for any context.
/// This component allows external contracts to implement custom prize addition
/// and claim hooks.
///
/// Storage is namespaced by `(context_owner, context_id)`. The `context_owner` is
/// the contract address that first calls `add_prize` for a given `context_id`;
/// further `add_prize` calls from the same owner append more prizes, but a
/// different caller cannot add prizes to an already-registered context.

#[starknet::component]
pub mod PrizeExtensionComponent {
    use metagame_extensions_interfaces::prize_extension::{IPRIZE_EXTENSION_ID, IPrizeExtension};
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
    pub trait PrizeExtension<TContractState> {
        /// Add a prize configuration for `(context_owner, context_id)`
        fn add_prize(
            ref self: TContractState,
            context_owner: ContractAddress,
            context_id: u64,
            prize_id: u64,
            config: Span<felt252>,
        );

        /// Claim a prize for a context
        fn claim_prize(
            ref self: TContractState,
            context_owner: ContractAddress,
            context_id: u64,
            claim_params: Span<felt252>,
        );
    }

    #[embeddable_as(PrizeExtensionImpl)]
    impl PrizeExtensionComponentImpl<
        TContractState,
        +HasComponent<TContractState>,
        +PrizeExtension<TContractState>,
        +SRC5Component::HasComponent<TContractState>,
        +Drop<TContractState>,
    > of IPrizeExtension<ComponentState<TContractState>> {
        fn is_context_registered(
            self: @ComponentState<TContractState>, context_owner: ContractAddress, context_id: u64,
        ) -> bool {
            self.context_registered.read((context_owner, context_id))
        }

        fn add_prize(
            ref self: ComponentState<TContractState>,
            context_id: u64,
            prize_id: u64,
            config: Span<felt252>,
        ) {
            let caller = get_caller_address();
            self.register_context_idempotent(caller, context_id);
            let mut contract = self.get_contract_mut();
            PrizeExtension::add_prize(ref contract, caller, context_id, prize_id, config);
        }

        fn claim_prize(
            ref self: ComponentState<TContractState>, context_id: u64, claim_params: Span<felt252>,
        ) {
            let caller = get_caller_address();
            self.assert_registered(caller, context_id);
            let mut contract = self.get_contract_mut();
            PrizeExtension::claim_prize(ref contract, caller, context_id, claim_params);
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
        }

        fn is_registered(
            self: @ComponentState<TContractState>, context_owner: ContractAddress, context_id: u64,
        ) -> bool {
            self.context_registered.read((context_owner, context_id))
        }

        /// Mark `(context_owner, context_id)` as registered. Idempotent —
        /// multiple `add_prize` calls from the same owner for the same context are allowed.
        fn register_context_idempotent(
            ref self: ComponentState<TContractState>,
            context_owner: ContractAddress,
            context_id: u64,
        ) {
            if !self.context_registered.read((context_owner, context_id)) {
                self.context_registered.write((context_owner, context_id), true);
            }
        }

        /// Assert `(context_owner, context_id)` has been registered.
        fn assert_registered(
            self: @ComponentState<TContractState>, context_owner: ContractAddress, context_id: u64,
        ) {
            assert!(
                self.context_registered.read((context_owner, context_id)),
                "Prize Extension: Context not registered",
            );
        }
    }
}
