//! ERC20 Balance Validator tests
//!
//! These exercise the single-pass `collect_player_balance_state` helper that backs
//! `validate_entry`, `entries_left`, and `should_ban_entry`. The token's `balance_of`
//! is mocked via `start_mock_call` against the fake address stored in config, so the
//! suite stays deterministic and doesn't require fork access.

use metagame_extensions_interfaces::entry_requirement_extension::{
    IEntryRequirementExtensionDispatcher, IEntryRequirementExtensionDispatcherTrait,
};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address, start_mock_call,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

const ONE_TOKEN: u128 = 1_000_000_000_000_000_000; // 1e18

fn owner_address() -> ContractAddress {
    0x1234.try_into().unwrap()
}

fn player1() -> ContractAddress {
    0x111.try_into().unwrap()
}

fn token_address() -> ContractAddress {
    0xaaaa.try_into().unwrap()
}

fn deploy_validator() -> ContractAddress {
    let contract = declare("ERC20BalanceValidator").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![]).unwrap();
    contract_address
}

/// Mock the token's `balance_of` to return `balance` for any caller.
fn mock_balance(balance: u256) {
    start_mock_call(token_address(), selector!("balance_of"), balance);
}

/// WAD-mode config: per-balance entry calculation. min/max/vpe in token units, max_entries
/// caps the resulting allowance, bannable=true so should_ban is exercised end-to-end.
fn configure_wad_mode(
    validator_address: ContractAddress,
    context_id: u64,
    min_threshold: u128,
    max_threshold: u128,
    value_per_entry: u128,
    max_entries: u32,
) {
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };
    let config = array![
        token_address().into(), min_threshold.into(),
        0, // min_threshold_high (always 0 in tests — values fit in u128)
        max_threshold.into(),
        0, // max_threshold_high
        value_per_entry.into(), 0, // value_per_entry_high
        max_entries.into(), 1 // bannable
    ];
    start_cheat_caller_address(validator_address, owner_address());
    validator.add_config(context_id, 0, config.span());
    stop_cheat_caller_address(validator_address);
}

/// Fixed-mode config: vpe=0, entry_limit gates per-player entries.
fn configure_fixed_mode(
    validator_address: ContractAddress, context_id: u64, min_threshold: u128, entry_limit: u32,
) {
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };
    let config = array![
        token_address().into(), min_threshold.into(), 0, 0, // max_threshold = 0 (no upper bound)
        0,
        0, // value_per_entry = 0 (fixed mode)
        0, 0, // max_entries unused
        0 // bannable = false
    ];
    start_cheat_caller_address(validator_address, owner_address());
    validator.add_config(context_id, entry_limit, config.span());
    stop_cheat_caller_address(validator_address);
}

#[test]
fn test_balance_below_min_threshold_rejects_entry() {
    let validator_address = deploy_validator();
    configure_wad_mode(validator_address, 1, 5 * ONE_TOKEN, 0, ONE_TOKEN, 0);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    // Balance = 3 tokens, below 5-token minimum.
    mock_balance(u256 { low: 3 * ONE_TOKEN, high: 0 });

    assert!(
        !validator.valid_entry(owner_address(), 1, player1(), array![].span()),
        "below-min should reject",
    );
}

#[test]
fn test_balance_above_max_threshold_rejects_entry() {
    let validator_address = deploy_validator();
    // min = 1, max = 10, vpe = 1
    configure_wad_mode(validator_address, 1, ONE_TOKEN, 10 * ONE_TOKEN, ONE_TOKEN, 0);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    // Balance = 50 tokens, well above max.
    mock_balance(u256 { low: 50 * ONE_TOKEN, high: 0 });

    assert!(
        !validator.valid_entry(owner_address(), 1, player1(), array![].span()),
        "above-max should reject",
    );
}

#[test]
fn test_balance_above_max_entries_left_is_zero() {
    // Behavior pin: pre-refactor, entries_left silently capped at max_threshold and reported
    // a positive number of entries even when validate_entry rejected. Now both align: above
    // max_threshold → 0 entries left.
    let validator_address = deploy_validator();
    configure_wad_mode(validator_address, 1, ONE_TOKEN, 10 * ONE_TOKEN, ONE_TOKEN, 0);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    mock_balance(u256 { low: 50 * ONE_TOKEN, high: 0 });

    let entries = validator.entries_left(owner_address(), 1, player1(), array![].span());
    assert!(entries == Option::Some(0), "entries_left must be 0 when balance > max");
}

#[test]
fn test_wad_mode_first_entry_passes_with_correct_allowance() {
    let validator_address = deploy_validator();
    // min = 1, no max, vpe = 1 → 9-token balance buys 8 entries.
    configure_wad_mode(validator_address, 1, ONE_TOKEN, 0, ONE_TOKEN, 0);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    mock_balance(u256 { low: 9 * ONE_TOKEN, high: 0 });

    assert!(
        validator.valid_entry(owner_address(), 1, player1(), array![].span()),
        "in-range first entry should pass",
    );

    let entries = validator.entries_left(owner_address(), 1, player1(), array![].span());
    assert!(entries == Option::Some(8), "entries_left should report 8");
}

#[test]
fn test_wad_mode_quota_exhausted_rejects() {
    let validator_address = deploy_validator();
    // min = 1, no max, vpe = 1 → 3-token balance = 2 entries.
    configure_wad_mode(validator_address, 1, ONE_TOKEN, 0, ONE_TOKEN, 0);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    mock_balance(u256 { low: 3 * ONE_TOKEN, high: 0 });

    // Burn through the 2 available entries.
    start_cheat_caller_address(validator_address, owner_address());
    validator.add_entry(1, 1, player1(), array![].span());
    validator.add_entry(1, 2, player1(), array![].span());
    stop_cheat_caller_address(validator_address);

    assert!(
        !validator.valid_entry(owner_address(), 1, player1(), array![].span()),
        "quota-exhausted player must be rejected by validate_entry",
    );

    let entries = validator.entries_left(owner_address(), 1, player1(), array![].span());
    assert!(entries == Option::Some(0), "entries_left should be 0 after exhaustion");
}

#[test]
fn test_wad_mode_max_entries_caps_allowance() {
    let validator_address = deploy_validator();
    // min = 0, no max, vpe = 1, max_entries = 5 → even a 1000-token balance only yields 5.
    configure_wad_mode(validator_address, 1, 0, 0, ONE_TOKEN, 5);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    mock_balance(u256 { low: 1000 * ONE_TOKEN, high: 0 });

    let entries = validator.entries_left(owner_address(), 1, player1(), array![].span());
    assert!(entries == Option::Some(5), "max_entries should cap the allowance");

    // And quota is enforced by validate_entry: 5 entries used → reject the 6th.
    start_cheat_caller_address(validator_address, owner_address());
    let mut i: u64 = 1;
    while i <= 5 {
        validator.add_entry(1, i.into(), player1(), array![].span());
        i += 1;
    }
    stop_cheat_caller_address(validator_address);

    assert!(
        !validator.valid_entry(owner_address(), 1, player1(), array![].span()),
        "validate_entry must reject once max_entries is reached",
    );
}

#[test]
fn test_fixed_mode_entry_limit_enforced() {
    let validator_address = deploy_validator();
    // min = 1, fixed mode, entry_limit = 2.
    configure_fixed_mode(validator_address, 1, ONE_TOKEN, 2);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    mock_balance(u256 { low: 100 * ONE_TOKEN, high: 0 });

    assert!(
        validator.valid_entry(owner_address(), 1, player1(), array![].span()),
        "first entry under fixed limit should pass",
    );

    start_cheat_caller_address(validator_address, owner_address());
    validator.add_entry(1, 1, player1(), array![].span());
    validator.add_entry(1, 2, player1(), array![].span());
    stop_cheat_caller_address(validator_address);

    assert!(
        !validator.valid_entry(owner_address(), 1, player1(), array![].span()),
        "validate_entry must reject once entry_limit is reached",
    );

    let entries = validator.entries_left(owner_address(), 1, player1(), array![].span());
    assert!(entries == Option::Some(0), "entries_left should reach 0");
}

#[test]
fn test_fixed_mode_unlimited_when_zero_limit() {
    let validator_address = deploy_validator();
    // entry_limit = 0 → unlimited.
    configure_fixed_mode(validator_address, 1, ONE_TOKEN, 0);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    mock_balance(u256 { low: ONE_TOKEN, high: 0 });

    let entries = validator.entries_left(owner_address(), 1, player1(), array![].span());
    assert!(entries == Option::None, "entry_limit = 0 should report unlimited");

    assert!(
        validator.valid_entry(owner_address(), 1, player1(), array![].span()),
        "unlimited mode should always admit eligible players",
    );
}

#[test]
fn test_should_ban_when_balance_drops_below_min() {
    let validator_address = deploy_validator();
    configure_wad_mode(validator_address, 1, 5 * ONE_TOKEN, 0, ONE_TOKEN, 0);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    mock_balance(u256 { low: 2 * ONE_TOKEN, high: 0 });

    let should_ban = validator.should_ban(owner_address(), 1, 1, player1(), array![].span());
    assert!(should_ban, "should_ban must be true when balance drops below min");
}

#[test]
fn test_should_ban_when_balance_exceeds_max() {
    let validator_address = deploy_validator();
    configure_wad_mode(validator_address, 1, ONE_TOKEN, 10 * ONE_TOKEN, ONE_TOKEN, 0);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    mock_balance(u256 { low: 50 * ONE_TOKEN, high: 0 });

    let should_ban = validator.should_ban(owner_address(), 1, 1, player1(), array![].span());
    assert!(should_ban, "should_ban must be true when balance exceeds max");
}

#[test]
fn test_should_ban_when_quota_exceeded_after_balance_decrease() {
    let validator_address = deploy_validator();
    configure_wad_mode(validator_address, 1, ONE_TOKEN, 0, ONE_TOKEN, 0);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    // Player initially had 10-token balance and used 5 entries (within their 9-entry quota).
    mock_balance(u256 { low: 10 * ONE_TOKEN, high: 0 });
    start_cheat_caller_address(validator_address, owner_address());
    let mut i: u64 = 1;
    while i <= 5 {
        validator.add_entry(1, i.into(), player1(), array![].span());
        i += 1;
    }
    stop_cheat_caller_address(validator_address);

    // Now their balance drops to 3 tokens → only 2 entries currently allowed → over quota.
    mock_balance(u256 { low: 3 * ONE_TOKEN, high: 0 });

    let should_ban = validator.should_ban(owner_address(), 1, 1, player1(), array![].span());
    assert!(should_ban, "should_ban must be true when used > current allowance");
}

#[test]
fn test_should_ban_false_when_within_quota() {
    let validator_address = deploy_validator();
    configure_wad_mode(validator_address, 1, ONE_TOKEN, 0, ONE_TOKEN, 0);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    mock_balance(u256 { low: 10 * ONE_TOKEN, high: 0 });

    start_cheat_caller_address(validator_address, owner_address());
    validator.add_entry(1, 1, player1(), array![].span());
    stop_cheat_caller_address(validator_address);

    let should_ban = validator.should_ban(owner_address(), 1, 1, player1(), array![].span());
    assert!(!should_ban, "should_ban must be false when within quota");
}

#[test]
fn test_should_ban_false_in_fixed_mode_when_balance_intact() {
    // Fixed-mode contexts are configured non-bannable in `configure_fixed_mode`, so the
    // framework short-circuits should_ban to false. This pins that behavior — quota
    // enforcement in fixed mode happens at validate_entry, never via banning.
    let validator_address = deploy_validator();
    configure_fixed_mode(validator_address, 1, ONE_TOKEN, 2);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    mock_balance(u256 { low: 5 * ONE_TOKEN, high: 0 });

    let should_ban = validator.should_ban(owner_address(), 1, 1, player1(), array![].span());
    assert!(!should_ban, "non-bannable fixed-mode context should never ban");
}

#[test]
#[should_panic(expected: "ERC20 Entry Validator: Qualification data invalid")]
fn test_qualification_data_must_be_empty() {
    let validator_address = deploy_validator();
    configure_wad_mode(validator_address, 1, ONE_TOKEN, 0, ONE_TOKEN, 0);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    mock_balance(u256 { low: 5 * ONE_TOKEN, high: 0 });

    let bad_qualification = array![1, 2, 3];
    validator.valid_entry(owner_address(), 1, player1(), bad_qualification.span());
}

#[test]
fn test_balance_at_exact_min_threshold_zero_entries_in_wad_mode() {
    // Edge case: balance == min_threshold → in range, but (balance - min) / vpe == 0.
    // Player passes the threshold check but has 0 entries available.
    let validator_address = deploy_validator();
    configure_wad_mode(validator_address, 1, 5 * ONE_TOKEN, 0, ONE_TOKEN, 0);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    mock_balance(u256 { low: 5 * ONE_TOKEN, high: 0 });

    let entries = validator.entries_left(owner_address(), 1, player1(), array![].span());
    assert!(entries == Option::Some(0), "exactly-min balance should yield 0 entries");

    // And validate_entry rejects because used (0) is not strictly less than allowed (0).
    assert!(
        !validator.valid_entry(owner_address(), 1, player1(), array![].span()),
        "exactly-min balance with 0 quota should be rejected",
    );
}

#[test]
fn test_wad_mode_overflow_caps_at_max_entries() {
    // Behavior pin: a player with a balance that overflows u32 entries (huge balance,
    // tiny value_per_entry) must end up at `max_entries`, not at 0. Pre-fix, the u256→u32
    // try_into fallback was 0, so a maximally-eligible player got rejected. Now the
    // overflow saturates to u32::MAX and `max_entries` clamps it to the configured cap.
    let validator_address = deploy_validator();
    // min = 0, no max_threshold, value_per_entry = 1 (smallest possible), max_entries = 10.
    configure_wad_mode(validator_address, 1, 0, 0, 1, 10);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    // Massive balance — the u256 entries division produces a value far beyond u32::MAX.
    mock_balance(u256 { low: 0xffffffffffffffffffffffffffffffff_u128, high: 0 });

    let entries = validator.entries_left(owner_address(), 1, player1(), array![].span());
    assert!(entries == Option::Some(10), "overflow must saturate then cap at max_entries");

    assert!(
        validator.valid_entry(owner_address(), 1, player1(), array![].span()),
        "overflow-eligible player must be admitted, not silently rejected",
    );
}

#[test]
fn test_fixed_mode_entries_left_zero_when_below_threshold() {
    // Behavior pin: fixed-mode entries_left now respects min_threshold (was previously
    // bypassed — entries_left reported entry_limit even when validate_entry would reject).
    let validator_address = deploy_validator();
    configure_fixed_mode(validator_address, 1, 5 * ONE_TOKEN, 5);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    // Balance well below the 5-token min.
    mock_balance(u256 { low: ONE_TOKEN, high: 0 });

    let entries = validator.entries_left(owner_address(), 1, player1(), array![].span());
    assert!(entries == Option::Some(0), "below-min in fixed mode must report 0 entries");

    assert!(
        !validator.valid_entry(owner_address(), 1, player1(), array![].span()),
        "validate_entry rejects below-min, entries_left now agrees",
    );
}

#[test]
fn test_fixed_mode_entries_left_zero_at_exact_limit() {
    // Saturation guard: when used_entries reaches entry_limit exactly, fixed-mode
    // entries_left returns 0 (and would not panic if a future config change pushed
    // used_entries past entry_limit).
    let validator_address = deploy_validator();
    configure_fixed_mode(validator_address, 1, ONE_TOKEN, 3);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    mock_balance(u256 { low: 10 * ONE_TOKEN, high: 0 });

    start_cheat_caller_address(validator_address, owner_address());
    let mut i: u64 = 1;
    while i <= 3 {
        validator.add_entry(1, i.into(), player1(), array![].span());
        i += 1;
    }
    stop_cheat_caller_address(validator_address);

    let entries = validator.entries_left(owner_address(), 1, player1(), array![].span());
    assert!(entries == Option::Some(0), "fixed-mode entries_left must saturate at 0");
}
