//! OpusTrovesValidator Fork Tests (Debt-Based)
//!
//! This test file demonstrates debt-based tournament entries:
//! - Entries scale with borrowed yin amount (summed across all troves)
//! - Forging yin increases entries
//! - Melting yin decreases entries (can trigger banning)

use metagame_extensions_interfaces::entry_requirement::{
    EntryRequirement, EntryRequirementType, ExtensionConfig,
};
use metagame_extensions_interfaces::entry_requirement_extension::{
    IEntryRequirementExtensionDispatcher, IEntryRequirementExtensionDispatcherTrait,
};
use metagame_extensions_interfaces::tournament::{
    GameConfig, ITournamentDispatcher, ITournamentDispatcherTrait, Metadata, Period, Schedule,
};
use metagame_extensions_presets::entry_requirement::externals::opus::AssetBalance;
use metagame_extensions_presets::entry_requirement::externals::wadray::Wad;
use metagame_extensions_presets::entry_requirement::opus_troves_validator::{
    IOpusTrovesValidatorDispatcher, IOpusTrovesValidatorDispatcherTrait,
};
use metagame_extensions_test_common::constants::{
    minigame_address_mainnet, test_account_mainnet, tournament_address_mainnet,
};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_block_timestamp_global,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::{ContractAddress, get_block_timestamp};

#[starknet::interface]
pub trait IERC20<TState> {
    fn approve(ref self: TState, spender: ContractAddress, amount: u256);
    fn balance_of(self: @TState, account: ContractAddress) -> u256;
}

#[starknet::interface]
pub trait IAbbot<TState> {
    fn open_trove(
        ref self: TState,
        yang_assets: Span<AssetBalance>,
        forge_amount: Wad,
        max_forge_fee_pct: Wad,
    ) -> u64;
    fn forge(ref self: TState, trove_id: u64, amount: Wad, max_forge_fee_pct: Wad);
    fn melt(ref self: TState, trove_id: u64, amount: Wad);
    fn get_user_trove_ids(self: @TState, user: ContractAddress) -> Span<u64>;
}

#[starknet::interface]
pub trait IShrine<TState> {
    fn get_trove_health(self: @TState, trove_id: u64) -> Health;
}

#[derive(Drop, Serde, Copy)]
pub struct Health {
    pub threshold: metagame_extensions_presets::entry_requirement::externals::wadray::Ray,
    pub ltv: metagame_extensions_presets::entry_requirement::externals::wadray::Ray,
    pub value: Wad,
    pub debt: Wad,
}

// Opus mainnet addresses
fn abbot_address() -> ContractAddress {
    0x04d0bb0a4c40012384e7c419e6eb3c637b28e8363fb66958b60d90505b9c072f.try_into().unwrap()
}

fn shrine_address() -> ContractAddress {
    0x0498edfaf50ca5855666a700c25dd629d577eb9afccdf3b5977aec79aee55ada.try_into().unwrap()
}

fn opus_strk_gate_address() -> ContractAddress {
    0x031a96FE18Fe3Fdab28822c82C81471f1802800723C8f3E209F1d9da53bC637D.try_into().unwrap()
}

fn strk_token_address() -> ContractAddress {
    0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d.try_into().unwrap()
}

// Deploy the OpusTrovesValidator contract
fn deploy_opus_validator(tournament_address: ContractAddress) -> ContractAddress {
    let contract = declare("OpusTrovesValidator").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![]).unwrap();
    contract_address
}

// Helper functions for creating tournaments
fn test_metadata() -> Metadata {
    Metadata { name: 'Opus V2 Tournament', description: "Debt-based tournament" }
}

fn test_game_config(minigame_address: ContractAddress) -> GameConfig {
    GameConfig { address: minigame_address, settings_id: 1, soulbound: false, play_url: "" }
}

fn test_schedule() -> Schedule {
    let current_time = get_block_timestamp();
    Schedule {
        registration: Option::Some(Period { start: current_time + 100, end: current_time + 4000 }),
        game: Period { start: current_time + 4001, end: current_time + 8000 },
        submission_duration: 3600,
    }
}

// ==============================================
// TEST: DEBT-BASED ENTRIES
// ==============================================

#[test]
#[fork("mainnet")]
fn test_opus_validator_debt_based() {
    // Test: Entries based on borrowed yin (debt)
    // Entries scale with how much yin has been borrowed against collateral

    let owner_addr = tournament_address_mainnet();
    let minigame_addr = minigame_address_mainnet();
    let account = test_account_mainnet();

    // Step 1: Deploy validator
    let validator_address = deploy_opus_validator(owner_addr);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };
    let validator_api = IOpusTrovesValidatorDispatcher { contract_address: validator_address };

    // Step 2: Create trove with STRK and forge yin
    let strk_token = IERC20Dispatcher { contract_address: strk_token_address() };
    let abbot = IAbbotDispatcher { contract_address: abbot_address() };

    start_cheat_caller_address(strk_token_address(), account);
    strk_token.approve(opus_strk_gate_address(), 1000000000000000000000);
    stop_cheat_caller_address(strk_token_address());

    let yang_asset = AssetBalance {
        address: strk_token_address(), amount: 1000000000000000000000 // 1000 STRK
    };

    start_cheat_caller_address(abbot_address(), account);
    let trove_id = abbot
        .open_trove(
            array![yang_asset].span(),
            20000000000000000000_u128.into(), // Forge 20 yin initially (well above threshold)
            10_u128.into() // 10% max fee
        );
    stop_cheat_caller_address(abbot_address());

    assert(trove_id > 0, 'Trove created');

    // Step 3: Get initial debt
    let shrine = IShrineDispatcher { contract_address: shrine_address() };
    let health_initial: Health = shrine.get_trove_health(trove_id);

    // Debt is in 18 decimals (yin decimals), not 36
    let _initial_debt_simple: u128 = health_initial.debt.val / 1000000000000000000;

    // Step 4: Configure validator for DEBT mode (wildcard - all troves)
    // Config format: [asset_count, threshold, value_per_entry, max_entries]
    // All values now in WAD units (18 decimals) for maximum precision
    let asset_count: u8 = 0; // 0 = wildcard (all troves)
    let threshold: u128 = 5000000000000000000; // 5 yin minimum (5e18)
    let value_per_entry: u128 = 2000000000000000000; // 2 yin per entry (2e18)
    let max_entries: u32 = 50;

    let extension_config = ExtensionConfig {
        address: validator_address,
        config: array![
            asset_count.into(), // Asset count (0 = wildcard)
            threshold.into(), // Threshold (wad units)
            value_per_entry.into(), // Value per entry (wad units)
            max_entries.into() // Max entries
        ]
            .span(),
    };

    let entry_requirement = EntryRequirement {
        entry_limit: 0, entry_requirement_type: EntryRequirementType::extension(extension_config),
    };

    // Step 5: Create tournament
    let platform = ITournamentDispatcher { contract_address: owner_addr };

    start_cheat_caller_address(owner_addr, account);
    let tournament = platform
        .create_tournament(
            account,
            test_metadata(),
            test_schedule(),
            test_game_config(minigame_addr),
            Option::None,
            Option::Some(entry_requirement),
        );
    stop_cheat_caller_address(owner_addr);

    assert(tournament.id > 0, 'Tournament created');

    // Step 6: Warp time to registration period
    let current_time = get_block_timestamp();
    start_cheat_block_timestamp_global(current_time + 200); // Move into registration period

    // Step 7: Verify configuration (wad units)
    assert(
        validator_api.get_debt_threshold(tournament.id) == 5000000000000000000,
        'Threshold mismatch',
    );
    assert(
        validator_api.get_value_per_entry(tournament.id) == 2000000000000000000,
        'Value per entry mismatch',
    );
    assert(validator_api.get_max_entries(tournament.id) == max_entries, 'Max entries mismatch');

    // Step 8: Debug - check if we can see the trove
    let abbot_check = IAbbotDispatcher { contract_address: abbot_address() };
    let _trove_ids = abbot_check.get_user_trove_ids(account);

    // Step 8: Validate entry and check entries based on initial debt
    let is_valid = validator.valid_entry(tournament.id, account, array![].span());
    assert(is_valid, 'Player should be valid');

    let entries_left_initial = validator.entries_left(tournament.id, account, array![].span());
    assert(entries_left_initial.is_some(), 'Should have entries');
    let initial_entries = entries_left_initial.unwrap();
    assert(initial_entries > 0, 'Should have initial entries');

    // Expected: (initial_debt_simple - 5) / 2
    // If initial_debt_simple = 20, then (20-5)/2 = 7 entries (capped at max_entries if needed)

    // Step 9: Exercise add/remove entry hooks directly
    start_cheat_caller_address(validator_address, owner_addr);
    validator.add_entry(tournament.id, 1, account, array![].span());
    stop_cheat_caller_address(validator_address);

    let entries_after_add = validator
        .entries_left(tournament.id, account, array![].span())
        .unwrap();
    assert(entries_after_add < initial_entries, 'add dec');

    start_cheat_caller_address(validator_address, owner_addr);
    validator.remove_entry(tournament.id, 1, account, array![].span());
    validator.remove_entry(tournament.id, 1, account, array![].span()); // no-op when zero
    stop_cheat_caller_address(validator_address);

    let entries_after_remove = validator
        .entries_left(tournament.id, account, array![].span())
        .unwrap();
    assert(entries_after_remove == initial_entries, 'rm rest');

    // Step 10: Forge more yin to increase debt
    start_cheat_caller_address(abbot_address(), account);
    abbot.forge(trove_id, 20000000000000000000_u128.into(), 10_u128.into()); // Forge 20 more yin
    stop_cheat_caller_address(abbot_address());

    // Step 11: Check new debt and entries
    let health_after_forge: Health = shrine.get_trove_health(trove_id);
    let _new_debt_simple: u128 = health_after_forge.debt.val / 1000000000000000000;

    let entries_left_after_forge = validator.entries_left(tournament.id, account, array![].span());
    let new_entries = entries_left_after_forge.unwrap();

    // Entries should have increased!
    // Expected: (new_debt_simple - 5) / 2
    // If new_debt_simple = 40, then (40-5)/2 = 17 entries
    assert(new_entries > initial_entries, 'Entries should increase');
}

// ==============================================
// TEST: DEBT THRESHOLD AND BANNING
// ==============================================

#[test]
#[fork("mainnet")]
fn test_opus_validator_debt_threshold_and_banning() {
    // Test: Melting yin below quota triggers banning

    let owner_addr = tournament_address_mainnet();
    let minigame_addr = minigame_address_mainnet();
    let account = test_account_mainnet();

    // Step 1: Deploy validator
    let validator_address = deploy_opus_validator(owner_addr);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    // Step 2: Create trove and forge significant debt
    let strk_token = IERC20Dispatcher { contract_address: strk_token_address() };
    let abbot = IAbbotDispatcher { contract_address: abbot_address() };

    start_cheat_caller_address(strk_token_address(), account);
    strk_token.approve(opus_strk_gate_address(), 1000000000000000000000);
    stop_cheat_caller_address(strk_token_address());

    let yang_asset = AssetBalance { address: strk_token_address(), amount: 1000000000000000000000 };

    start_cheat_caller_address(abbot_address(), account);
    let trove_id = abbot
        .open_trove(
            array![yang_asset].span(),
            30000000000000000000_u128.into(), // Forge 30 yin (safer LTV)
            10_u128.into() // 10% max fee
        );
    stop_cheat_caller_address(abbot_address());

    // Step 3: Configure with higher threshold (wildcard mode, wad units)
    let asset_count: u8 = 0; // 0 = wildcard (all troves)
    let threshold: u128 = 10000000000000000000; // 10 yin (10e18)
    let value_per_entry: u128 = 5000000000000000000; // 5 yin per entry (5e18)
    let max_entries: u32 = 20;

    let extension_config = ExtensionConfig {
        address: validator_address,
        config: array![
            asset_count.into(), threshold.into(), value_per_entry.into(), max_entries.into(),
        ]
            .span(),
    };

    let entry_requirement = EntryRequirement {
        entry_limit: 0, entry_requirement_type: EntryRequirementType::extension(extension_config),
    };

    let platform = ITournamentDispatcher { contract_address: owner_addr };

    start_cheat_caller_address(owner_addr, account);
    let tournament = platform
        .create_tournament(
            account,
            test_metadata(),
            test_schedule(),
            test_game_config(minigame_addr),
            Option::None,
            Option::Some(entry_requirement),
        );
    stop_cheat_caller_address(owner_addr);

    // Step 4: Warp time to registration period
    let current_time = get_block_timestamp();
    start_cheat_block_timestamp_global(current_time + 200); // Move into registration period

    // Step 5: Check initial state - should be valid
    let is_valid_initial = validator.valid_entry(tournament.id, account, array![].span());
    assert(is_valid_initial, 'Should be valid initially');

    let _initial_entries = validator.entries_left(tournament.id, account, array![].span()).unwrap();
    // Expected: (30-10)/5 = 4 entries

    // Step 6: Melt yin to drop below threshold
    // Account may have pre-existing trove debt at this block, so melt aggressively
    start_cheat_caller_address(abbot_address(), account);
    abbot
        .melt(
            trove_id, 28000000000000000000_u128.into(),
        ); // Melt 28 yin, leaving ~2 (well below 10 threshold)
    stop_cheat_caller_address(abbot_address());

    // Step 7: Should now be invalid (below threshold)
    let is_valid_after_melt = validator.valid_entry(tournament.id, account, array![].span());
    assert(!is_valid_after_melt, 'Should be invalid');

    // Existing entries should now be bannable
    let should_ban = validator.should_ban(tournament.id, 1, account, array![].span());
    assert(should_ban, 'should ban');
}

// ==============================================
// TEST: ASSET FILTERING
// ==============================================

#[test]
#[fork("mainnet")]
fn test_opus_validator_asset_filtering() {
    // Test: Only count debt from troves backed by specific assets (STRK)

    let owner_addr = tournament_address_mainnet();
    let minigame_addr = minigame_address_mainnet();
    let account = test_account_mainnet();

    // Step 1: Deploy validator
    let validator_address = deploy_opus_validator(owner_addr);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    // Step 2: Create trove with STRK
    let strk_token = IERC20Dispatcher { contract_address: strk_token_address() };
    let abbot = IAbbotDispatcher { contract_address: abbot_address() };

    start_cheat_caller_address(strk_token_address(), account);
    strk_token.approve(opus_strk_gate_address(), 1000000000000000000000);
    stop_cheat_caller_address(strk_token_address());

    let yang_asset = AssetBalance {
        address: strk_token_address(), amount: 1000000000000000000000 // 1000 STRK
    };

    start_cheat_caller_address(abbot_address(), account);
    let _trove_id = abbot
        .open_trove(
            array![yang_asset].span(),
            20000000000000000000_u128.into(), // Forge 20 yin
            10_u128.into() // 10% max fee
        );
    stop_cheat_caller_address(abbot_address());

    // Step 3: Configure with STRK filter (wad units)
    let asset_count: u8 = 1; // Filter by 1 asset
    let threshold: u128 = 5000000000000000000; // 5 yin minimum (5e18)
    let value_per_entry: u128 = 2000000000000000000; // 2 yin per entry (2e18)
    let max_entries: u32 = 50;

    let extension_config = ExtensionConfig {
        address: validator_address,
        config: array![
            asset_count.into(), // 1 asset filter
            strk_token_address().into(), // STRK address
            threshold.into(), // Threshold (wad)
            value_per_entry.into(), // Value per entry (wad)
            max_entries.into() // Max entries
        ]
            .span(),
    };

    let entry_requirement = EntryRequirement {
        entry_limit: 0, entry_requirement_type: EntryRequirementType::extension(extension_config),
    };

    let platform = ITournamentDispatcher { contract_address: owner_addr };

    start_cheat_caller_address(owner_addr, account);
    let tournament = platform
        .create_tournament(
            account,
            test_metadata(),
            test_schedule(),
            test_game_config(minigame_addr),
            Option::None,
            Option::Some(entry_requirement),
        );
    stop_cheat_caller_address(owner_addr);

    // Step 4: Warp time to registration period
    let current_time = get_block_timestamp();
    start_cheat_block_timestamp_global(current_time + 200);

    // Step 5: Validate - should work because trove is backed by STRK
    let is_valid = validator.valid_entry(tournament.id, account, array![].span());
    assert(is_valid, 'Should be valid with STRK');

    let entries = validator.entries_left(tournament.id, account, array![].span()).unwrap();
    assert(entries > 0, 'Should have entries');
}

// ==============================================
// TEST: CONFIG FORMAT VALIDATION
// ==============================================

#[test]
#[fork("mainnet")]
fn test_opus_validator_config_zero_threshold() {
    // Test: Config with threshold=0, value_per_entry=1 (simple units, not wei)

    let owner_addr = tournament_address_mainnet();
    let minigame_addr = minigame_address_mainnet();
    let account = test_account_mainnet();

    // Step 1: Deploy validator
    let validator_address = deploy_opus_validator(owner_addr);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };
    let validator_api = IOpusTrovesValidatorDispatcher { contract_address: validator_address };

    // Step 2: Create trove with STRK and forge yin
    let strk_token = IERC20Dispatcher { contract_address: strk_token_address() };
    let abbot = IAbbotDispatcher { contract_address: abbot_address() };

    start_cheat_caller_address(strk_token_address(), account);
    strk_token.approve(opus_strk_gate_address(), 1000000000000000000000);
    stop_cheat_caller_address(strk_token_address());

    let yang_asset = AssetBalance {
        address: strk_token_address(), amount: 1000000000000000000000 // 1000 STRK
    };

    start_cheat_caller_address(abbot_address(), account);
    let _trove_id = abbot
        .open_trove(
            array![yang_asset].span(),
            5000000000000000000_u128.into(), // Forge 5 yin (5e18 in wad)
            10_u128.into(),
        );
    stop_cheat_caller_address(abbot_address());

    // Step 3: Test config with wad units: [0, 0, 1e18, 0]
    // IMPORTANT: threshold and value_per_entry are now in WAD UNITS (18 decimals)
    // - asset_count: 0 (wildcard)
    // - threshold: 0 (no minimum)
    // - value_per_entry: 1e18 (1 yin per entry in wad units)
    // - max_entries: 0 (unlimited)
    let asset_count: u8 = 0;
    let threshold: u128 = 0; // 0 yin minimum
    let value_per_entry: u128 = 1000000000000000000; // 1 yin per entry (1e18 wad)
    let max_entries: u32 = 0;

    let extension_config = ExtensionConfig {
        address: validator_address,
        config: array![
            asset_count.into(), threshold.into(), value_per_entry.into(), max_entries.into(),
        ]
            .span(),
    };

    let entry_requirement = EntryRequirement {
        entry_limit: 0, entry_requirement_type: EntryRequirementType::extension(extension_config),
    };

    let platform = ITournamentDispatcher { contract_address: owner_addr };

    start_cheat_caller_address(owner_addr, account);
    let tournament = platform
        .create_tournament(
            account,
            test_metadata(),
            test_schedule(),
            test_game_config(minigame_addr),
            Option::None,
            Option::Some(entry_requirement),
        );
    stop_cheat_caller_address(owner_addr);

    // Step 4: Warp time to registration period
    let current_time = get_block_timestamp();
    start_cheat_block_timestamp_global(current_time + 200);

    // Step 5: Verify config was stored correctly (wad units)
    assert(validator_api.get_debt_threshold(tournament.id) == 0, 'Threshold should be 0');
    assert(
        validator_api.get_value_per_entry(tournament.id) == 1000000000000000000,
        'Value per entry = 1e18',
    );
    assert(validator_api.get_max_entries(tournament.id) == 0, 'Max entries should be 0');

    // Step 6: Check that config works (threshold=0 means any debt is valid)
    let is_valid = validator.valid_entry(tournament.id, account, array![].span());
    assert(is_valid, 'Should be valid');

    let entries = validator.entries_left(tournament.id, account, array![].span()).unwrap();

    // With threshold=0 and value_per_entry=1e18, entries = total_debt_wad / 1e18
    // Should have at least 5 entries (may be more if account has existing debt)
    assert(entries >= 5, 'Should have at least 5');
}
