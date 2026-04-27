//! Opus Troves Validator tests
//!
//! These exercise the unified single-pass `collect_player_trove_state` helper that backs
//! `validate_entry`, `entries_left`, and `should_ban_entry`. Opus contracts are mocked at
//! their mainnet addresses via `start_mock_call`, so the suite stays deterministic and
//! doesn't require fork access.

use metagame_extensions_interfaces::entry_requirement_extension::{
    IEntryRequirementExtensionDispatcher, IEntryRequirementExtensionDispatcherTrait,
};
use metagame_extensions_presets::entry_requirement::externals::wadray::{Ray, Wad};
use metagame_extensions_presets::entry_requirement::opus_troves_validator::Health;
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address, start_mock_call,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

const ONE_YIN: u128 = 1_000_000_000_000_000_000; // 1e18

fn abbot_address() -> ContractAddress {
    0x04d0bb0a4c40012384e7c419e6eb3c637b28e8363fb66958b60d90505b9c072f.try_into().unwrap()
}

fn shrine_address() -> ContractAddress {
    0x0498edfaf50ca5855666a700c25dd629d577eb9afccdf3b5977aec79aee55ada.try_into().unwrap()
}

fn owner_address() -> ContractAddress {
    0x1234.try_into().unwrap()
}

fn player1() -> ContractAddress {
    0x111.try_into().unwrap()
}

fn strk_address() -> ContractAddress {
    0x4718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d.try_into().unwrap()
}

fn deploy_opus_validator() -> ContractAddress {
    let contract = declare("OpusTrovesValidator").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![]).unwrap();
    contract_address
}

/// Build a Health struct with the given debt (in wad units). The other fields are not
/// inspected by the validator but must be present for serde.
fn health_with_debt(debt_wad: u128) -> Health {
    Health {
        threshold: Ray { val: 0 },
        ltv: Ray { val: 0 },
        value: Wad { val: 0 },
        debt: Wad { val: debt_wad },
    }
}

/// Wildcard-mode config: no asset filter. threshold + value_per_entry + max_entries +
/// bannable.
fn configure_wildcard(
    validator_address: ContractAddress,
    context_id: u64,
    threshold_wad: u128,
    value_per_entry_wad: u128,
    max_entries: u32,
) {
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };
    let config = array![
        0, // asset_count = 0 (wildcard)
        threshold_wad.into(), value_per_entry_wad.into(),
        max_entries.into(), 1 // bannable
    ];
    start_cheat_caller_address(validator_address, owner_address());
    validator.add_config(context_id, 0, config.span());
    stop_cheat_caller_address(validator_address);
}

/// Single-asset filter config in fixed-mode (value_per_entry = 0). entry_limit is the
/// per-player cap.
fn configure_strk_fixed(
    validator_address: ContractAddress, context_id: u64, threshold_wad: u128, entry_limit: u32,
) {
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };
    let config = array![
        1, // asset_count = 1
        strk_address().into(), // STRK filter
        threshold_wad.into(),
        0, // value_per_entry = 0 (fixed mode)
        0, // max_entries unused in fixed mode
        0 // bannable = false
    ];
    start_cheat_caller_address(validator_address, owner_address());
    validator.add_config(context_id, entry_limit, config.span());
    stop_cheat_caller_address(validator_address);
}

#[test]
fn test_no_troves_rejects_entry() {
    let validator_address = deploy_opus_validator();
    configure_wildcard(validator_address, 1, ONE_YIN, ONE_YIN, 0);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    // Player owns no troves.
    let empty_troves: Span<u64> = array![].span();
    start_mock_call(abbot_address(), selector!("get_user_trove_ids"), empty_troves);

    assert!(
        !validator.valid_entry(owner_address(), 1, player1(), array![].span()),
        "no troves should reject",
    );
}

#[test]
fn test_debt_below_threshold_rejects_entry() {
    let validator_address = deploy_opus_validator();
    // threshold = 5 yin
    configure_wildcard(validator_address, 1, 5 * ONE_YIN, ONE_YIN, 0);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    let troves: Span<u64> = array![42_u64].span();
    start_mock_call(abbot_address(), selector!("get_user_trove_ids"), troves);
    // debt = 3 yin, below the 5-yin threshold.
    start_mock_call(shrine_address(), selector!("get_trove_health"), health_with_debt(3 * ONE_YIN));

    assert!(
        !validator.valid_entry(owner_address(), 1, player1(), array![].span()),
        "debt below threshold should reject",
    );
}

#[test]
fn test_wad_mode_first_entry_passes() {
    let validator_address = deploy_opus_validator();
    // threshold = 1 yin, 1 yin per entry → 9 yin debt buys 8 entries (after threshold).
    configure_wildcard(validator_address, 1, ONE_YIN, ONE_YIN, 0);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    let troves: Span<u64> = array![42_u64].span();
    start_mock_call(abbot_address(), selector!("get_user_trove_ids"), troves);
    start_mock_call(shrine_address(), selector!("get_trove_health"), health_with_debt(9 * ONE_YIN));

    assert!(
        validator.valid_entry(owner_address(), 1, player1(), array![].span()),
        "fresh player above threshold should pass",
    );

    let entries = validator.entries_left(owner_address(), 1, player1(), array![].span());
    assert!(entries == Option::Some(8), "entries_left should report 8");
}

#[test]
fn test_wad_mode_quota_exhausted_rejects() {
    let validator_address = deploy_opus_validator();
    // threshold = 1 yin, 1 yin per entry → 3 yin debt = 2 entries available.
    configure_wildcard(validator_address, 1, ONE_YIN, ONE_YIN, 0);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    let troves: Span<u64> = array![42_u64].span();
    start_mock_call(abbot_address(), selector!("get_user_trove_ids"), troves);
    start_mock_call(shrine_address(), selector!("get_trove_health"), health_with_debt(3 * ONE_YIN));

    // Burn through the 2 available entries.
    start_cheat_caller_address(validator_address, owner_address());
    validator.add_entry(1, 1, player1(), array![].span());
    validator.add_entry(1, 2, player1(), array![].span());
    stop_cheat_caller_address(validator_address);

    assert!(
        !validator.valid_entry(owner_address(), 1, player1(), array![].span()),
        "quota-exhausted player should be rejected by validate_entry",
    );

    let entries = validator.entries_left(owner_address(), 1, player1(), array![].span());
    assert!(entries == Option::Some(0), "entries_left should be 0 after exhaustion");
}

#[test]
fn test_wad_mode_max_entries_caps_allowance() {
    let validator_address = deploy_opus_validator();
    // 0 threshold, 1 yin per entry, max_entries = 5. Even with 100 yin debt the player
    // tops out at 5 entries.
    configure_wildcard(validator_address, 1, 0, ONE_YIN, 5);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    let troves: Span<u64> = array![42_u64].span();
    start_mock_call(abbot_address(), selector!("get_user_trove_ids"), troves);
    start_mock_call(
        shrine_address(), selector!("get_trove_health"), health_with_debt(100 * ONE_YIN),
    );

    let entries = validator.entries_left(owner_address(), 1, player1(), array![].span());
    assert!(entries == Option::Some(5), "max_entries should cap the allowance");
}

#[test]
fn test_fixed_mode_entry_limit_enforced() {
    let validator_address = deploy_opus_validator();
    // STRK filter, threshold = 1 yin, fixed mode, entry_limit = 2.
    configure_strk_fixed(validator_address, 1, ONE_YIN, 2);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    let troves: Span<u64> = array![7_u64].span();
    start_mock_call(abbot_address(), selector!("get_user_trove_ids"), troves);
    // Trove has STRK collateral (matches filter) and enough debt.
    start_mock_call(abbot_address(), selector!("get_trove_asset_balance"), 100_u128);
    start_mock_call(shrine_address(), selector!("get_trove_health"), health_with_debt(5 * ONE_YIN));

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
        "validate_entry should reject once entry_limit is reached",
    );
}

#[test]
fn test_asset_filter_excludes_non_matching_trove() {
    let validator_address = deploy_opus_validator();
    configure_strk_fixed(validator_address, 1, ONE_YIN, 2);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    let troves: Span<u64> = array![99_u64].span();
    start_mock_call(abbot_address(), selector!("get_user_trove_ids"), troves);
    // No STRK in this trove → filter excludes it; debt should sum to 0 → below threshold.
    start_mock_call(abbot_address(), selector!("get_trove_asset_balance"), 0_u128);
    // get_trove_health should never be called for an excluded trove, but stub it anyway in
    // case the implementation regresses.
    start_mock_call(
        shrine_address(), selector!("get_trove_health"), health_with_debt(50 * ONE_YIN),
    );

    assert!(
        !validator.valid_entry(owner_address(), 1, player1(), array![].span()),
        "trove with no matching asset should not contribute debt",
    );
}

#[test]
fn test_should_ban_when_debt_drops_below_threshold() {
    let validator_address = deploy_opus_validator();
    // threshold = 5 yin, 1 yin per entry.
    configure_wildcard(validator_address, 1, 5 * ONE_YIN, ONE_YIN, 0);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    let troves: Span<u64> = array![42_u64].span();
    start_mock_call(abbot_address(), selector!("get_user_trove_ids"), troves);
    // Debt has dropped to 2 yin, well below the 5-yin threshold.
    start_mock_call(shrine_address(), selector!("get_trove_health"), health_with_debt(2 * ONE_YIN));

    let should_ban = validator.should_ban(owner_address(), 1, 1, player1(), array![].span());
    assert!(should_ban, "should_ban must be true when debt drops below threshold");
}

#[test]
fn test_should_ban_false_when_within_quota() {
    let validator_address = deploy_opus_validator();
    configure_wildcard(validator_address, 1, ONE_YIN, ONE_YIN, 0);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    let troves: Span<u64> = array![42_u64].span();
    start_mock_call(abbot_address(), selector!("get_user_trove_ids"), troves);
    // 10 yin debt → 9 entries allowed. Player has used 1 → still well within quota.
    start_mock_call(
        shrine_address(), selector!("get_trove_health"), health_with_debt(10 * ONE_YIN),
    );

    start_cheat_caller_address(validator_address, owner_address());
    validator.add_entry(1, 1, player1(), array![].span());
    stop_cheat_caller_address(validator_address);

    let should_ban = validator.should_ban(owner_address(), 1, 1, player1(), array![].span());
    assert!(!should_ban, "should_ban must be false when within quota");
}

#[test]
fn test_should_ban_when_quota_exceeded_after_debt_decrease() {
    let validator_address = deploy_opus_validator();
    configure_wildcard(validator_address, 1, ONE_YIN, ONE_YIN, 0);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    let troves: Span<u64> = array![42_u64].span();
    start_mock_call(abbot_address(), selector!("get_user_trove_ids"), troves);
    // Player initially had high debt and used 5 entries…
    start_mock_call(
        shrine_address(), selector!("get_trove_health"), health_with_debt(10 * ONE_YIN),
    );

    start_cheat_caller_address(validator_address, owner_address());
    let mut i: u64 = 1;
    while i <= 5 {
        validator.add_entry(1, i.into(), player1(), array![].span());
        i += 1;
    }
    stop_cheat_caller_address(validator_address);

    // …then melted yin so their debt now only buys 2 entries, leaving them over quota.
    start_mock_call(shrine_address(), selector!("get_trove_health"), health_with_debt(3 * ONE_YIN));

    let should_ban = validator.should_ban(owner_address(), 1, 1, player1(), array![].span());
    assert!(should_ban, "should_ban must be true when used > current allowance");
}

#[test]
fn test_entries_left_unlimited_in_fixed_mode_with_zero_limit() {
    let validator_address = deploy_opus_validator();
    // entry_limit = 0 → unlimited
    configure_strk_fixed(validator_address, 1, ONE_YIN, 0);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    let entries = validator.entries_left(owner_address(), 1, player1(), array![].span());
    assert!(entries == Option::None, "entry_limit = 0 should report unlimited");
}
