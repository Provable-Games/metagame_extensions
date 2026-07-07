//! # Adventurer Oracle
//!
//! A reusable, general objective-checker over Death Mountain adventurer NFTs. Layer 1
//! of the beast-mode achievement system: an owner registers objectives (any adventurer
//! metric + comparator + threshold, scoped to a game `settings_id`), and anyone can ask
//! whether a given adventurer token has completed a given objective.
//!
//! It implements the game-components `IMinigameObjectives` / `IMinigameObjectivesDetails`
//! objective component interface, generalizing the score-only implementation in
//! `super-death-mountain/contracts/src/systems/game_token.cairo` to any adventurer
//! attribute.
//!
//! ## Data flow (per the contract-layer pattern: validate -> fetch -> pure eval)
//! `completed_objective(token_id, objective_id)`:
//!   1. objective must exist (else `false`);
//!   2. the token's `settings_id` (from the token source) must equal the objective's
//!      configured `settings_id` (else `false`);
//!   3. fetch the live `(Adventurer, Bag)` from the adventurer source;
//!   4. delegate the decision to the pure `oracle_lib::evaluate` (or, for `ItemSet*`
//!      objectives, to `oracle_lib::evaluate_item_set` with the stored item id list).
//!
//! ## Objective kinds
//! - Scalar / single-item objectives are registered via `create_objective`.
//! - Item-set objectives ("hold N of these item ids") are registered via
//!   `create_item_set_objective`, which stores the item id list; the `ItemSet*` metrics
//!   compare the count of held set items against `config.target`.
//!
//! ## Later layers
//! The thin metagame *validator* (`presets/.../entry_requirement/adventurer_validator.cairo`)
//! implements the Budokan `entry_requirement` interface by delegating `validate_entry` to
//! this oracle's `completed_objective` for a configured objective id.

#[starknet::contract]
pub mod AdventurerOracle {
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_introspection::src5::SRC5Component::InternalTrait as SRC5InternalTrait;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};
    use crate::interface::{
        GameObjective, GameObjectiveDetails, IAdventurerOracle, IAdventurerStateSourceDispatcher,
        IAdventurerStateSourceDispatcherTrait, IGameSettingsSourceDispatcher,
        IGameSettingsSourceDispatcherTrait, IMINIGAME_OBJECTIVES_ID, IMinigameObjectives,
        IMinigameObjectivesDetails, ITokenSettingsSourceDispatcher,
        ITokenSettingsSourceDispatcherTrait, Metric, ObjectiveConfig,
    };
    use crate::oracle_lib;

    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;
    impl SRC5InternalImpl = SRC5Component::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        owner: ContractAddress,
        // Source contracts (see interface docs for the production mapping).
        adventurer_source: ContractAddress,
        token_source: ContractAddress,
        settings_source: ContractAddress,
        // Objective registry: ids are sequential 1..=objective_count.
        objective_count: u32,
        objectives: Map<u32, ObjectiveConfig>,
        objective_name: Map<u32, ByteArray>,
        objective_description: Map<u32, ByteArray>,
        // Item id set for `ItemSet*` objectives (empty otherwise).
        objective_item_len: Map<u32, u32>,
        objective_items: Map<(u32, u32), u8>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        SRC5Event: SRC5Component::Event,
        ObjectiveCreated: ObjectiveCreated,
        OwnershipTransferred: OwnershipTransferred,
    }

    #[derive(Drop, starknet::Event)]
    struct ObjectiveCreated {
        #[key]
        objective_id: u32,
        settings_id: u32,
    }

    #[derive(Drop, starknet::Event)]
    struct OwnershipTransferred {
        #[key]
        previous_owner: ContractAddress,
        #[key]
        new_owner: ContractAddress,
    }

    pub mod Errors {
        pub const ZERO_OWNER: felt252 = 'Oracle: owner is zero';
        pub const NOT_OWNER: felt252 = 'Oracle: caller not owner';
        pub const SETTINGS_MISSING: felt252 = 'Oracle: settings do not exist';
        pub const OBJECTIVE_MISSING: felt252 = 'Oracle: objective missing';
        pub const SET_METRIC_NEEDS_ITEMS: felt252 = 'Oracle: use item_set create';
        pub const NOT_SET_METRIC: felt252 = 'Oracle: not an item-set metric';
        pub const EMPTY_ITEM_SET: felt252 = 'Oracle: item set is empty';
        pub const ZERO_ITEM_ID: felt252 = 'Oracle: item id is zero';
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        adventurer_source: ContractAddress,
        token_source: ContractAddress,
        settings_source: ContractAddress,
    ) {
        assert(owner.into() != 0, Errors::ZERO_OWNER);
        self.owner.write(owner);
        self.adventurer_source.write(adventurer_source);
        self.token_source.write(token_source);
        self.settings_source.write(settings_source);
        self.src5.register_interface(IMINIGAME_OBJECTIVES_ID);
    }

    // -------------------------------------------------------------------
    // Objective component conformance
    // -------------------------------------------------------------------

    #[abi(embed_v0)]
    impl ObjectivesImpl of IMinigameObjectives<ContractState> {
        fn objective_exists(self: @ContractState, objective_id: u32) -> bool {
            objective_id != 0 && objective_id <= self.objective_count.read()
        }

        fn completed_objective(self: @ContractState, token_id: felt252, objective_id: u32) -> bool {
            if !self.objective_exists(objective_id) {
                return false;
            }
            let config = self.objectives.read(objective_id);

            // Validate the token was minted with the objective's settings.
            let token_settings = ITokenSettingsSourceDispatcher {
                contract_address: self.token_source.read(),
            }
                .settings_id(token_id);
            if token_settings != config.settings_id {
                return false;
            }

            // Fetch live adventurer state and evaluate with the pure lib.
            let (adventurer, bag) = IAdventurerStateSourceDispatcher {
                contract_address: self.adventurer_source.read(),
            }
                .load_assets(token_id);
            if oracle_lib::is_item_set_metric(config.metric) {
                let items = self.read_objective_items(objective_id);
                oracle_lib::evaluate_item_set(adventurer, bag, items, config)
            } else {
                oracle_lib::evaluate(adventurer, bag, config)
            }
        }

        fn objective_exists_batch(self: @ContractState, objective_ids: Span<u32>) -> Array<bool> {
            let mut results: Array<bool> = array![];
            for id in objective_ids {
                results.append(self.objective_exists(*id));
            }
            results
        }
    }

    #[abi(embed_v0)]
    impl ObjectivesDetailsImpl of IMinigameObjectivesDetails<ContractState> {
        fn objectives_count(self: @ContractState) -> u32 {
            self.objective_count.read()
        }

        fn objectives_details(self: @ContractState, objective_id: u32) -> GameObjectiveDetails {
            assert(self.objective_exists(objective_id), Errors::OBJECTIVE_MISSING);
            let config = self.objectives.read(objective_id);
            let name = self.objective_name.read(objective_id);
            let description = self.objective_description.read(objective_id);

            let objectives = array![
                GameObjective { name: 'Metric', value: metric_name(config.metric) },
                GameObjective { name: 'Comparator', value: comparator_name(config.comparator) },
                GameObjective { name: 'Target', value: config.target.into() },
                GameObjective { name: 'Aux', value: config.aux.into() },
                GameObjective { name: 'Settings Id', value: config.settings_id.into() },
            ];

            GameObjectiveDetails { name, description, objectives: objectives.span() }
        }

        fn objectives_details_batch(
            self: @ContractState, objective_ids: Span<u32>,
        ) -> Array<GameObjectiveDetails> {
            let mut results: Array<GameObjectiveDetails> = array![];
            for id in objective_ids {
                results.append(self.objectives_details(*id));
            }
            results
        }
    }

    // -------------------------------------------------------------------
    // Admin / read interface
    // -------------------------------------------------------------------

    #[abi(embed_v0)]
    impl AdventurerOracleImpl of IAdventurerOracle<ContractState> {
        fn create_objective(
            ref self: ContractState,
            name: ByteArray,
            description: ByteArray,
            config: ObjectiveConfig,
        ) -> u32 {
            self.assert_only_owner();
            // Item-set metrics carry an item id list and must use
            // `create_item_set_objective`.
            assert(!oracle_lib::is_item_set_metric(config.metric), Errors::SET_METRIC_NEEDS_ITEMS);
            self.register_objective(name, description, config)
        }

        fn create_item_set_objective(
            ref self: ContractState,
            name: ByteArray,
            description: ByteArray,
            config: ObjectiveConfig,
            items: Span<u8>,
        ) -> u32 {
            self.assert_only_owner();
            assert(oracle_lib::is_item_set_metric(config.metric), Errors::NOT_SET_METRIC);
            assert(items.len() != 0, Errors::EMPTY_ITEM_SET);
            for item_id in items {
                assert(*item_id != 0, Errors::ZERO_ITEM_ID);
            }

            let objective_id = self.register_objective(name, description, config);

            // Persist the item id set alongside the objective.
            self.objective_item_len.write(objective_id, items.len());
            let mut index: u32 = 0;
            for item_id in items {
                self.objective_items.write((objective_id, index), *item_id);
                index += 1;
            }
            objective_id
        }

        fn get_objective(self: @ContractState, objective_id: u32) -> ObjectiveConfig {
            assert(self.objective_exists(objective_id), Errors::OBJECTIVE_MISSING);
            self.objectives.read(objective_id)
        }

        fn get_objective_items(self: @ContractState, objective_id: u32) -> Array<u8> {
            assert(self.objective_exists(objective_id), Errors::OBJECTIVE_MISSING);
            let len = self.objective_item_len.read(objective_id);
            let mut items: Array<u8> = array![];
            let mut index: u32 = 0;
            while index != len {
                items.append(self.objective_items.read((objective_id, index)));
                index += 1;
            }
            items
        }

        fn owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }

        fn transfer_ownership(ref self: ContractState, new_owner: ContractAddress) {
            self.assert_only_owner();
            assert(new_owner.into() != 0, Errors::ZERO_OWNER);
            let previous_owner = self.owner.read();
            self.owner.write(new_owner);
            self.emit(OwnershipTransferred { previous_owner, new_owner });
        }

        fn adventurer_source(self: @ContractState) -> ContractAddress {
            self.adventurer_source.read()
        }

        fn token_source(self: @ContractState) -> ContractAddress {
            self.token_source.read()
        }

        fn settings_source(self: @ContractState) -> ContractAddress {
            self.settings_source.read()
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn assert_only_owner(self: @ContractState) {
            assert(get_caller_address() == self.owner.read(), Errors::NOT_OWNER);
        }

        /// Validate settings + assign the next sequential id and persist the shared
        /// objective fields (config/name/description). Callers add any metric-specific
        /// state (e.g. the item set) afterwards. Assumes ownership was already checked.
        fn register_objective(
            ref self: ContractState,
            name: ByteArray,
            description: ByteArray,
            config: ObjectiveConfig,
        ) -> u32 {
            let exists = IGameSettingsSourceDispatcher {
                contract_address: self.settings_source.read(),
            }
                .settings_exist(config.settings_id);
            assert(exists, Errors::SETTINGS_MISSING);

            let objective_id = self.objective_count.read() + 1;
            self.objective_count.write(objective_id);
            self.objectives.write(objective_id, config);
            self.objective_name.write(objective_id, name);
            self.objective_description.write(objective_id, description);

            self.emit(ObjectiveCreated { objective_id, settings_id: config.settings_id });
            objective_id
        }

        /// Read the stored item id set for an objective as a span.
        fn read_objective_items(self: @ContractState, objective_id: u32) -> Span<u8> {
            let len = self.objective_item_len.read(objective_id);
            let mut items: Array<u8> = array![];
            let mut index: u32 = 0;
            while index != len {
                items.append(self.objective_items.read((objective_id, index)));
                index += 1;
            }
            items.span()
        }
    }

    fn metric_name(metric: Metric) -> felt252 {
        match metric {
            Metric::Xp => 'Xp',
            Metric::Level => 'Level',
            Metric::Gold => 'Gold',
            Metric::Health => 'Health',
            Metric::BeastHealth => 'BeastHealth',
            Metric::StatUpgradesAvailable => 'StatUpgradesAvailable',
            Metric::Strength => 'Strength',
            Metric::Dexterity => 'Dexterity',
            Metric::Vitality => 'Vitality',
            Metric::Intelligence => 'Intelligence',
            Metric::Wisdom => 'Wisdom',
            Metric::Charisma => 'Charisma',
            Metric::Luck => 'Luck',
            Metric::ItemHeldAnywhere => 'ItemHeldAnywhere',
            Metric::ItemEquipped => 'ItemEquipped',
            Metric::ItemInBag => 'ItemInBag',
            Metric::ItemGreatness => 'ItemGreatness',
            Metric::ItemSetHeldAnywhere => 'ItemSetHeldAnywhere',
            Metric::ItemSetEquipped => 'ItemSetEquipped',
            Metric::ItemSetInBag => 'ItemSetInBag',
        }
    }

    fn comparator_name(comparator: crate::interface::Comparator) -> felt252 {
        match comparator {
            crate::interface::Comparator::AtLeast => 'AtLeast',
            crate::interface::Comparator::AtMost => 'AtMost',
            crate::interface::Comparator::Equal => 'Equal',
            crate::interface::Comparator::GreaterThan => 'GreaterThan',
            crate::interface::Comparator::LessThan => 'LessThan',
            crate::interface::Comparator::NotEqual => 'NotEqual',
        }
    }
}
