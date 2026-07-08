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
//! ## Objective model
//! An objective is a CONJUNCTION: it is complete iff the token's `settings_id` matches,
//! every registered `Condition` passes (each a single metric check — scalar or a
//! single-item check), AND the adventurer holds all of the objective's optional item
//! set. So a simple goal ("reach level 10") is one condition, a composite goal
//! ("score + gold + holds an item") is several, and "own this whole set of items" is
//! the objective's `items` list — all through the single `create_objective` entrypoint.
//!
//! ## Data flow (per the contract-layer pattern: validate -> fetch -> pure eval)
//! `completed_objective(token_id, objective_id)`:
//!   1. objective must exist (else `false`);
//!   2. the token's `settings_id` must equal the objective's `settings_id` (else `false`);
//!   3. fetch the live `(Adventurer, Bag)` from the adventurer source;
//!   4. AND every condition (`oracle_lib::evaluate_condition`) and the item set
//!      (`oracle_lib::holds_all_items`).
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
        Condition, GameObjective, GameObjectiveDetails, IAdventurerOracle,
        IAdventurerStateSourceDispatcher, IAdventurerStateSourceDispatcherTrait,
        IGameSettingsSourceDispatcher, IGameSettingsSourceDispatcherTrait, IMINIGAME_OBJECTIVES_ID,
        IMinigameObjectives, IMinigameObjectivesDetails, ITokenSettingsSourceDispatcher,
        ITokenSettingsSourceDispatcherTrait, Metric,
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
        objective_settings_id: Map<u32, u32>,
        // Conditions per objective (all ANDed).
        objective_condition_count: Map<u32, u32>,
        objective_conditions: Map<(u32, u32), Condition>,
        // Required item id set per objective (0 length => no set requirement).
        objective_item_count: Map<u32, u32>,
        objective_items: Map<(u32, u32), u8>,
        objective_name: Map<u32, ByteArray>,
        objective_description: Map<u32, ByteArray>,
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
        pub const NO_REQUIREMENTS: felt252 = 'Oracle: objective is empty';
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

            // Validate the token was minted with the objective's settings.
            let token_settings = ITokenSettingsSourceDispatcher {
                contract_address: self.token_source.read(),
            }
                .settings_id(token_id);
            if token_settings != self.objective_settings_id.read(objective_id) {
                return false;
            }

            // Fetch live adventurer state once, then AND every condition + the item set.
            let (adventurer, bag) = IAdventurerStateSourceDispatcher {
                contract_address: self.adventurer_source.read(),
            }
                .load_assets(token_id);

            let count = self.objective_condition_count.read(objective_id);
            let mut i: u32 = 0;
            while i != count {
                let condition = self.objective_conditions.read((objective_id, i));
                if !oracle_lib::evaluate_condition(adventurer, bag, condition) {
                    return false;
                }
                i += 1;
            }

            oracle_lib::holds_all_items(adventurer, bag, self.read_objective_items(objective_id))
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
            let name = self.objective_name.read(objective_id);
            let description = self.objective_description.read(objective_id);

            let mut objectives: Array<GameObjective> = array![
                GameObjective {
                    name: 'Settings Id',
                    value: self.objective_settings_id.read(objective_id).into(),
                },
            ];
            // One detail row per condition (metric + comparator + target).
            let count = self.objective_condition_count.read(objective_id);
            let mut i: u32 = 0;
            while i != count {
                let c = self.objective_conditions.read((objective_id, i));
                objectives
                    .append(GameObjective { name: metric_name(c.metric), value: c.target.into() });
                objectives
                    .append(
                        GameObjective { name: 'Comparator', value: comparator_name(c.comparator) },
                    );
                i += 1;
            }
            // One row listing how many items the set requires.
            let item_count = self.objective_item_count.read(objective_id);
            if item_count != 0 {
                objectives
                    .append(GameObjective { name: 'Items Required', value: item_count.into() });
            }

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
            settings_id: u32,
            conditions: Array<Condition>,
            items: Option<Array<u8>>,
        ) -> u32 {
            self.assert_only_owner();

            // Validate the referenced game settings exist.
            let exists = IGameSettingsSourceDispatcher {
                contract_address: self.settings_source.read(),
            }
                .settings_exist(settings_id);
            assert(exists, Errors::SETTINGS_MISSING);

            let item_list: Array<u8> = items.unwrap_or_default();
            // An objective must require SOMETHING.
            assert(conditions.len() != 0 || item_list.len() != 0, Errors::NO_REQUIREMENTS);

            let objective_id = self.objective_count.read() + 1;
            self.objective_count.write(objective_id);
            self.objective_settings_id.write(objective_id, settings_id);

            // Persist the conditions.
            self.objective_condition_count.write(objective_id, conditions.len());
            let mut i: u32 = 0;
            for condition in conditions {
                self.objective_conditions.write((objective_id, i), condition);
                i += 1;
            }

            // Persist the required item set (each id non-zero).
            self.objective_item_count.write(objective_id, item_list.len());
            let mut j: u32 = 0;
            for item_id in item_list {
                assert(item_id != 0, Errors::ZERO_ITEM_ID);
                self.objective_items.write((objective_id, j), item_id);
                j += 1;
            }

            self.objective_name.write(objective_id, name);
            self.objective_description.write(objective_id, description);

            self.emit(ObjectiveCreated { objective_id, settings_id });
            objective_id
        }

        fn get_objective_settings_id(self: @ContractState, objective_id: u32) -> u32 {
            assert(self.objective_exists(objective_id), Errors::OBJECTIVE_MISSING);
            self.objective_settings_id.read(objective_id)
        }

        fn get_objective_conditions(self: @ContractState, objective_id: u32) -> Array<Condition> {
            assert(self.objective_exists(objective_id), Errors::OBJECTIVE_MISSING);
            let count = self.objective_condition_count.read(objective_id);
            let mut conditions: Array<Condition> = array![];
            let mut i: u32 = 0;
            while i != count {
                conditions.append(self.objective_conditions.read((objective_id, i)));
                i += 1;
            }
            conditions
        }

        fn get_objective_items(self: @ContractState, objective_id: u32) -> Array<u8> {
            assert(self.objective_exists(objective_id), Errors::OBJECTIVE_MISSING);
            let mut items: Array<u8> = array![];
            let count = self.objective_item_count.read(objective_id);
            let mut i: u32 = 0;
            while i != count {
                items.append(self.objective_items.read((objective_id, i)));
                i += 1;
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

        /// The required item id set for an objective, as a span (for the pure lib).
        fn read_objective_items(self: @ContractState, objective_id: u32) -> Span<u8> {
            let count = self.objective_item_count.read(objective_id);
            let mut items: Array<u8> = array![];
            let mut i: u32 = 0;
            while i != count {
                items.append(self.objective_items.read((objective_id, i)));
                i += 1;
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
