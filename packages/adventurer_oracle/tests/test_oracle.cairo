use metagame_extensions_adventurer_oracle::interface::{
    Comparator, IAdventurerOracleDispatcher, IAdventurerOracleDispatcherTrait,
    IMinigameObjectivesDetailsDispatcher, IMinigameObjectivesDetailsDispatcherTrait,
    IMinigameObjectivesDispatcher, IMinigameObjectivesDispatcherTrait, Metric, ObjectiveConfig,
};
use metagame_extensions_adventurer_oracle::mock_game::{
    IMockGameDispatcher, IMockGameDispatcherTrait,
};
use metagame_extensions_adventurer_oracle::oracle_lib;
use metagame_extensions_adventurer_oracle::types::{Adventurer, Bag, Equipment, Item, Stats};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

// ---------------------------------------------------------------------------
// Builders
// ---------------------------------------------------------------------------

fn owner_addr() -> ContractAddress {
    0x0abc.try_into().unwrap()
}

fn stranger_addr() -> ContractAddress {
    0x0dead.try_into().unwrap()
}

fn empty_item() -> Item {
    Item { id: 0, xp: 0 }
}

fn item(id: u8, xp: u16) -> Item {
    Item { id, xp }
}

fn empty_equipment() -> Equipment {
    Equipment {
        weapon: empty_item(),
        chest: empty_item(),
        head: empty_item(),
        waist: empty_item(),
        foot: empty_item(),
        hand: empty_item(),
        neck: empty_item(),
        ring: empty_item(),
    }
}

fn zero_stats() -> Stats {
    Stats {
        strength: 0, dexterity: 0, vitality: 0, intelligence: 0, wisdom: 0, charisma: 0, luck: 0,
    }
}

fn empty_bag() -> Bag {
    Bag {
        item_1: empty_item(),
        item_2: empty_item(),
        item_3: empty_item(),
        item_4: empty_item(),
        item_5: empty_item(),
        item_6: empty_item(),
        item_7: empty_item(),
        item_8: empty_item(),
        item_9: empty_item(),
        item_10: empty_item(),
        item_11: empty_item(),
        item_12: empty_item(),
        item_13: empty_item(),
        item_14: empty_item(),
        item_15: empty_item(),
        mutated: false,
    }
}

fn base_adventurer() -> Adventurer {
    Adventurer {
        health: 100,
        xp: 0,
        gold: 0,
        beast_health: 0,
        stat_upgrades_available: 0,
        stats: zero_stats(),
        equipment: empty_equipment(),
        item_specials_salt: 0,
        beast_salt: 0,
        level_salt: 0,
    }
}

fn config(metric: Metric, comparator: Comparator, target: u64, aux: u64) -> ObjectiveConfig {
    ObjectiveConfig { settings_id: 0, metric, comparator, target, aux }
}

// ---------------------------------------------------------------------------
// Pure library tests (no deployment)
// ---------------------------------------------------------------------------

#[test]
fn test_level_from_xp_floor_is_one() {
    assert!(oracle_lib::level_from_xp(0) == 1, "xp 0 -> level 1");
    assert!(oracle_lib::level_from_xp(1) == 1, "xp 1 -> level 1");
    assert!(oracle_lib::level_from_xp(3) == 1, "xp 3 -> level 1");
    assert!(oracle_lib::level_from_xp(4) == 2, "xp 4 -> level 2");
    assert!(oracle_lib::level_from_xp(100) == 10, "xp 100 -> level 10");
    assert!(oracle_lib::level_from_xp(400) == 20, "xp 400 -> level 20");
}

#[test]
fn test_item_greatness() {
    assert!(oracle_lib::item_greatness(0) == 0, "xp 0 -> greatness 0");
    assert!(oracle_lib::item_greatness(1) == 1, "xp 1 -> greatness 1");
    assert!(oracle_lib::item_greatness(400) == 20, "xp 400 -> greatness 20");
    // Capped at 20.
    assert!(oracle_lib::item_greatness(65535) == 20, "cap at 20");
}

#[test]
fn test_compare_all_comparators() {
    assert!(oracle_lib::compare(10, Comparator::AtLeast, 10), "10 >= 10");
    assert!(!oracle_lib::compare(9, Comparator::AtLeast, 10), "9 !>= 10");
    assert!(oracle_lib::compare(10, Comparator::AtMost, 10), "10 <= 10");
    assert!(!oracle_lib::compare(11, Comparator::AtMost, 10), "11 !<= 10");
    assert!(oracle_lib::compare(10, Comparator::Equal, 10), "10 == 10");
    assert!(!oracle_lib::compare(11, Comparator::Equal, 10), "11 != 10");
    assert!(oracle_lib::compare(11, Comparator::GreaterThan, 10), "11 > 10");
    assert!(!oracle_lib::compare(10, Comparator::GreaterThan, 10), "10 !> 10");
    assert!(oracle_lib::compare(9, Comparator::LessThan, 10), "9 < 10");
    assert!(!oracle_lib::compare(10, Comparator::LessThan, 10), "10 !< 10");
    assert!(oracle_lib::compare(11, Comparator::NotEqual, 10), "11 != 10");
    assert!(!oracle_lib::compare(10, Comparator::NotEqual, 10), "10 == 10 fails NotEqual");
}

#[test]
fn test_evaluate_scalar_metrics() {
    let mut adv = base_adventurer();
    adv.xp = 400;
    adv.gold = 250;
    adv.health = 80;
    adv.beast_health = 30;
    adv.stat_upgrades_available = 3;
    adv.stats.strength = 15;
    adv.stats.dexterity = 7;
    adv.stats.vitality = 9;
    adv.stats.intelligence = 4;
    adv.stats.wisdom = 6;
    adv.stats.charisma = 11;
    adv.stats.luck = 21;
    let bag = empty_bag();

    assert!(oracle_lib::evaluate(adv, bag, config(Metric::Xp, Comparator::AtLeast, 400, 0)), "xp");
    assert!(
        oracle_lib::evaluate(adv, bag, config(Metric::Level, Comparator::AtLeast, 20, 0)), "level",
    );
    assert!(
        oracle_lib::evaluate(adv, bag, config(Metric::Gold, Comparator::AtLeast, 250, 0)), "gold",
    );
    assert!(
        oracle_lib::evaluate(adv, bag, config(Metric::Health, Comparator::Equal, 80, 0)), "health",
    );
    assert!(
        oracle_lib::evaluate(adv, bag, config(Metric::BeastHealth, Comparator::AtMost, 30, 0)),
        "beast",
    );
    assert!(
        oracle_lib::evaluate(
            adv, bag, config(Metric::StatUpgradesAvailable, Comparator::Equal, 3, 0),
        ),
        "upgrades",
    );
    assert!(
        oracle_lib::evaluate(adv, bag, config(Metric::Strength, Comparator::GreaterThan, 10, 0)),
        "str",
    );
    assert!(
        oracle_lib::evaluate(adv, bag, config(Metric::Dexterity, Comparator::Equal, 7, 0)), "dex",
    );
    assert!(
        oracle_lib::evaluate(adv, bag, config(Metric::Vitality, Comparator::Equal, 9, 0)), "vit",
    );
    assert!(
        oracle_lib::evaluate(adv, bag, config(Metric::Intelligence, Comparator::Equal, 4, 0)),
        "int",
    );
    assert!(oracle_lib::evaluate(adv, bag, config(Metric::Wisdom, Comparator::Equal, 6, 0)), "wis");
    assert!(
        oracle_lib::evaluate(adv, bag, config(Metric::Charisma, Comparator::Equal, 11, 0)), "cha",
    );
    assert!(
        oracle_lib::evaluate(adv, bag, config(Metric::Luck, Comparator::AtLeast, 20, 0)), "luck",
    );

    // Negative case.
    assert!(
        !oracle_lib::evaluate(adv, bag, config(Metric::Xp, Comparator::AtLeast, 401, 0)),
        "xp 400 !>= 401",
    );
}

#[test]
fn test_evaluate_item_equipped() {
    let mut adv = base_adventurer();
    adv.equipment.chest = item(42, 100);
    let bag = empty_bag();

    assert!(
        oracle_lib::evaluate(adv, bag, config(Metric::ItemEquipped, Comparator::Equal, 42, 0)),
        "equipped 42",
    );
    assert!(
        !oracle_lib::evaluate(adv, bag, config(Metric::ItemEquipped, Comparator::Equal, 7, 0)),
        "not equipped 7",
    );
    // Equipped counts as held-anywhere.
    assert!(
        oracle_lib::evaluate(adv, bag, config(Metric::ItemHeldAnywhere, Comparator::Equal, 42, 0)),
        "held 42",
    );
    // Equipped item is not in bag.
    assert!(
        !oracle_lib::evaluate(adv, bag, config(Metric::ItemInBag, Comparator::Equal, 42, 0)),
        "not in bag",
    );
}

#[test]
fn test_evaluate_item_in_bag_and_held_anywhere() {
    let mut adv = base_adventurer();
    let mut bag = empty_bag();
    bag.item_9 = item(77, 50);

    assert!(
        oracle_lib::evaluate(adv, bag, config(Metric::ItemInBag, Comparator::Equal, 77, 0)),
        "in bag 77",
    );
    assert!(
        oracle_lib::evaluate(adv, bag, config(Metric::ItemHeldAnywhere, Comparator::Equal, 77, 0)),
        "held 77",
    );
    assert!(
        !oracle_lib::evaluate(adv, bag, config(Metric::ItemEquipped, Comparator::Equal, 77, 0)),
        "not equipped 77",
    );
    // Item id beyond u8 range is unsatisfiable.
    assert!(
        !oracle_lib::evaluate(
            adv, bag, config(Metric::ItemHeldAnywhere, Comparator::Equal, 999, 0),
        ),
        "oversized id",
    );
}

#[test]
fn test_evaluate_item_greatness() {
    let mut adv = base_adventurer();
    adv.equipment.weapon = item(5, 100); // greatness 10
    let mut bag = empty_bag();
    bag.item_1 = item(5, 225); // greatness 15 (max copy)

    // aux is the greatness threshold; comparator applied to greatness.
    assert!(
        oracle_lib::evaluate(adv, bag, config(Metric::ItemGreatness, Comparator::AtLeast, 5, 15)),
        "max greatness 15 >= 15",
    );
    assert!(
        !oracle_lib::evaluate(adv, bag, config(Metric::ItemGreatness, Comparator::AtLeast, 5, 16)),
        "max greatness 15 !>= 16",
    );
    // Absent item -> greatness 0.
    assert!(
        !oracle_lib::evaluate(adv, bag, config(Metric::ItemGreatness, Comparator::AtLeast, 9, 1)),
        "absent item greatness 0",
    );
}

#[test]
#[fuzzer]
fn test_fuzz_xp_atleast_matches_direct_compare(xp: u16, target: u16) {
    let mut adv = base_adventurer();
    adv.xp = xp;
    let cfg = config(Metric::Xp, Comparator::AtLeast, target.into(), 0);
    let expected = xp >= target;
    assert!(oracle_lib::evaluate(adv, empty_bag(), cfg) == expected, "fuzz xp atleast");
}

#[test]
#[fuzzer]
fn test_fuzz_level_monotonic(xp: u16) {
    // Level is sqrt(xp) with a floor of 1: always between 1 and xp (for xp>=1).
    let level = oracle_lib::level_from_xp(xp);
    assert!(level >= 1, "level floor 1");
    assert!(level * level <= xp.into() || xp == 0, "level^2 <= xp");
}

// ---------------------------------------------------------------------------
// Integration tests (deploy mock + oracle)
// ---------------------------------------------------------------------------

fn deploy_mock() -> IMockGameDispatcher {
    let contract = declare("MockGame").unwrap().contract_class();
    let (addr, _) = contract.deploy(@array![]).unwrap();
    IMockGameDispatcher { contract_address: addr }
}

fn deploy_oracle(source: ContractAddress) -> IAdventurerOracleDispatcher {
    let contract = declare("AdventurerOracle").unwrap().contract_class();
    let mut calldata: Array<felt252> = array![];
    owner_addr().serialize(ref calldata);
    source.serialize(ref calldata); // adventurer_source
    source.serialize(ref calldata); // token_source
    source.serialize(ref calldata); // settings_source
    let (addr, _) = contract.deploy(@calldata).unwrap();
    IAdventurerOracleDispatcher { contract_address: addr }
}

/// Deploy a mock game + oracle wired together, with settings 0 and 1 registered.
fn setup() -> (IMockGameDispatcher, IAdventurerOracleDispatcher) {
    let mock = deploy_mock();
    mock.set_settings_exists(0, true);
    mock.set_settings_exists(1, true);
    let oracle = deploy_oracle(mock.contract_address);
    (mock, oracle)
}

fn create(oracle: IAdventurerOracleDispatcher, config: ObjectiveConfig) -> u32 {
    start_cheat_caller_address(oracle.contract_address, owner_addr());
    let id = oracle.create_objective("name", "desc", config);
    stop_cheat_caller_address(oracle.contract_address);
    id
}

#[test]
fn test_create_objective_increments_ids() {
    let (_mock, oracle) = setup();
    let id1 = create(oracle, config(Metric::Xp, Comparator::AtLeast, 100, 0));
    let id2 = create(oracle, config(Metric::Gold, Comparator::AtLeast, 50, 0));
    assert!(id1 == 1, "first id is 1");
    assert!(id2 == 2, "second id is 2");

    let objectives = IMinigameObjectivesDispatcher { contract_address: oracle.contract_address };
    assert!(objectives.objective_exists(1), "obj 1 exists");
    assert!(objectives.objective_exists(2), "obj 2 exists");
    assert!(!objectives.objective_exists(3), "obj 3 missing");
    assert!(!objectives.objective_exists(0), "obj 0 missing");

    let stored = oracle.get_objective(1);
    assert!(stored.target == 100, "stored target");
    assert!(stored.metric == Metric::Xp, "stored metric");
}

#[test]
#[should_panic(expected: 'Oracle: caller not owner')]
fn test_create_objective_only_owner() {
    let (_mock, oracle) = setup();
    start_cheat_caller_address(oracle.contract_address, stranger_addr());
    oracle.create_objective("n", "d", config(Metric::Xp, Comparator::AtLeast, 1, 0));
}

#[test]
#[should_panic(expected: 'Oracle: settings do not exist')]
fn test_create_objective_unknown_settings() {
    let (_mock, oracle) = setup();
    // settings_id 5 was never registered on the mock.
    create(
        oracle,
        ObjectiveConfig {
            settings_id: 5, metric: Metric::Xp, comparator: Comparator::AtLeast, target: 1, aux: 0,
        },
    );
}

#[test]
fn test_completed_objective_xp() {
    let (mock, oracle) = setup();
    let id = create(oracle, config(Metric::Xp, Comparator::AtLeast, 400, 0));
    let objectives = IMinigameObjectivesDispatcher { contract_address: oracle.contract_address };

    let token_id: felt252 = 111;
    mock.set_token_settings(token_id, 0);

    let mut adv = base_adventurer();
    adv.xp = 399;
    mock.set_assets(token_id, adv, empty_bag());
    assert!(!objectives.completed_objective(token_id, id), "xp 399 not complete");

    adv.xp = 400;
    mock.set_assets(token_id, adv, empty_bag());
    assert!(objectives.completed_objective(token_id, id), "xp 400 complete");
}

#[test]
fn test_completed_objective_equipped_item() {
    let (mock, oracle) = setup();
    let id = create(oracle, config(Metric::ItemEquipped, Comparator::Equal, 42, 0));
    let objectives = IMinigameObjectivesDispatcher { contract_address: oracle.contract_address };

    let token_id: felt252 = 222;
    mock.set_token_settings(token_id, 0);

    let mut adv = base_adventurer();
    adv.equipment.ring = item(42, 10);
    mock.set_assets(token_id, adv, empty_bag());
    assert!(objectives.completed_objective(token_id, id), "ring 42 equipped");

    let adv2 = base_adventurer();
    mock.set_assets(token_id, adv2, empty_bag());
    assert!(!objectives.completed_objective(token_id, id), "no item equipped");
}

#[test]
fn test_completed_objective_bag_item() {
    let (mock, oracle) = setup();
    let id = create(oracle, config(Metric::ItemInBag, Comparator::Equal, 88, 0));
    let objectives = IMinigameObjectivesDispatcher { contract_address: oracle.contract_address };

    let token_id: felt252 = 333;
    mock.set_token_settings(token_id, 0);

    let mut bag = empty_bag();
    bag.item_5 = item(88, 5);
    mock.set_assets(token_id, base_adventurer(), bag);
    assert!(objectives.completed_objective(token_id, id), "item 88 in bag");
}

#[test]
fn test_settings_id_mismatch_returns_false() {
    let (mock, oracle) = setup();
    // Objective requires settings_id 1.
    let id = create(
        oracle,
        ObjectiveConfig {
            settings_id: 1, metric: Metric::Xp, comparator: Comparator::AtLeast, target: 1, aux: 0,
        },
    );
    let objectives = IMinigameObjectivesDispatcher { contract_address: oracle.contract_address };

    let token_id: felt252 = 444;
    // Token was minted with settings_id 0 (mismatch).
    mock.set_token_settings(token_id, 0);
    let mut adv = base_adventurer();
    adv.xp = 1000; // would otherwise satisfy the objective
    mock.set_assets(token_id, adv, empty_bag());

    assert!(!objectives.completed_objective(token_id, id), "settings mismatch -> false");

    // Now align the token's settings.
    mock.set_token_settings(token_id, 1);
    assert!(objectives.completed_objective(token_id, id), "settings match -> true");
}

#[test]
fn test_unknown_objective_returns_false() {
    let (mock, oracle) = setup();
    let objectives = IMinigameObjectivesDispatcher { contract_address: oracle.contract_address };
    let token_id: felt252 = 555;
    mock.set_token_settings(token_id, 0);
    mock.set_assets(token_id, base_adventurer(), empty_bag());
    // Objective 99 never created.
    assert!(!objectives.completed_objective(token_id, 99), "unknown objective -> false");
}

#[test]
fn test_batch_helpers_and_details() {
    let (_mock, oracle) = setup();
    let id1 = create(oracle, config(Metric::Xp, Comparator::AtLeast, 100, 0));
    let id2 = create(oracle, config(Metric::Level, Comparator::AtLeast, 5, 0));

    let objectives = IMinigameObjectivesDispatcher { contract_address: oracle.contract_address };
    let exist = objectives.objective_exists_batch(array![id1, id2, 99].span());
    assert!(*exist.at(0), "id1 exists");
    assert!(*exist.at(1), "id2 exists");
    assert!(!*exist.at(2), "99 missing");

    let details = IMinigameObjectivesDetailsDispatcher {
        contract_address: oracle.contract_address,
    };
    assert!(details.objectives_count() == 2, "count 2");
    let d = details.objectives_details(id1);
    assert!(d.objectives.len() == 5, "5 detail rows");
    let batch = details.objectives_details_batch(array![id1, id2].span());
    assert!(batch.len() == 2, "batch len 2");
}

#[test]
fn test_transfer_ownership() {
    let (_mock, oracle) = setup();
    assert!(oracle.owner() == owner_addr(), "initial owner");

    start_cheat_caller_address(oracle.contract_address, owner_addr());
    oracle.transfer_ownership(stranger_addr());
    stop_cheat_caller_address(oracle.contract_address);
    assert!(oracle.owner() == stranger_addr(), "new owner");

    // New owner can create; settings 0 is registered.
    start_cheat_caller_address(oracle.contract_address, stranger_addr());
    let id = oracle.create_objective("n", "d", config(Metric::Gold, Comparator::AtLeast, 1, 0));
    stop_cheat_caller_address(oracle.contract_address);
    assert!(id == 1, "new owner created objective");
}
