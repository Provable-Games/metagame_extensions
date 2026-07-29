//! Adventurer Validator tests
//!
//! The objectives provider (oracle) is mocked via `start_mock_call` on
//! `completed_objective`, so the suite is deterministic and needs no fork access or the
//! oracle crate. It exercises the delegation + quota logic that backs `validate_entry`,
//! `entries_left`, and `should_ban_entry`.

use metagame_extensions_interfaces::entry_requirement_extension::{
    IEntryRequirementExtensionDispatcher, IEntryRequirementExtensionDispatcherTrait,
};
use metagame_extensions_presets::entry_requirement::adventurer_validator::{
    IAdventurerValidatorDispatcher, IAdventurerValidatorDispatcherTrait,
};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address, start_mock_call,
    stop_cheat_caller_address, stop_mock_call,
};
use starknet::ContractAddress;

fn oracle_address() -> ContractAddress {
    0x0ac1e.try_into().unwrap()
}

fn owner_address() -> ContractAddress {
    0x1234.try_into().unwrap()
}

fn player1() -> ContractAddress {
    0x111.try_into().unwrap()
}

const OBJECTIVE_ID: u32 = 7;
const ADVENTURER_TOKEN: felt252 = 4242;

fn deploy_adventurer_validator() -> ContractAddress {
    let contract = declare("AdventurerValidator").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![]).unwrap();
    contract_address
}

/// Configure a context: oracle + objective id, given per-player entry_limit, non-bannable.
fn configure(validator_address: ContractAddress, context_id: u64, entry_limit: u32) {
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };
    let config = array![oracle_address().into(), OBJECTIVE_ID.into()];
    start_cheat_caller_address(validator_address, owner_address());
    validator.add_config(context_id, entry_limit, config.span());
    stop_cheat_caller_address(validator_address);
}

/// Configure a bannable context.
fn configure_bannable(validator_address: ContractAddress, context_id: u64, entry_limit: u32) {
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };
    let config = array![oracle_address().into(), OBJECTIVE_ID.into(), 1];
    start_cheat_caller_address(validator_address, owner_address());
    validator.add_config(context_id, entry_limit, config.span());
    stop_cheat_caller_address(validator_address);
}

fn set_completed(completed: bool) {
    start_mock_call(oracle_address(), selector!("completed_objective"), completed);
}

fn qualification() -> Span<felt252> {
    array![ADVENTURER_TOKEN].span()
}

#[test]
fn test_objective_incomplete_rejects_entry() {
    let validator_address = deploy_adventurer_validator();
    configure(validator_address, 1, 0);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    set_completed(false);
    assert!(
        !validator.valid_entry(owner_address(), 1, player1(), qualification()),
        "incomplete objective should reject",
    );
}

#[test]
fn test_objective_complete_unlimited_grants_entry() {
    let validator_address = deploy_adventurer_validator();
    configure(validator_address, 1, 0); // entry_limit 0 = unlimited
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    set_completed(true);
    assert!(
        validator.valid_entry(owner_address(), 1, player1(), qualification()),
        "completed objective should grant entry",
    );
    // Unlimited => entries_left is None.
    assert!(
        validator.entries_left(owner_address(), 1, player1(), qualification()) == Option::None,
        "unlimited should report None",
    );
}

#[test]
fn test_unconfigured_context_rejects() {
    let validator_address = deploy_adventurer_validator();
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    // No add_config for context 99 => oracle is zero => reject regardless of completion.
    set_completed(true);
    assert!(
        !validator.valid_entry(owner_address(), 99, player1(), qualification()),
        "unconfigured context should reject",
    );
}

#[test]
fn test_empty_qualification_rejects() {
    let validator_address = deploy_adventurer_validator();
    configure(validator_address, 1, 0);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    set_completed(true);
    assert!(
        !validator.valid_entry(owner_address(), 1, player1(), array![].span()),
        "missing token_id should reject",
    );
}

#[test]
fn test_entry_limit_quota_enforced() {
    let validator_address = deploy_adventurer_validator();
    configure(validator_address, 1, 2); // limit of 2 entries
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };
    set_completed(true);

    // Start with full quota.
    assert!(
        validator.entries_left(owner_address(), 1, player1(), qualification()) == Option::Some(2),
        "should start with 2 entries",
    );

    // Consume both entries (add_entry is only callable by the registered context owner).
    start_cheat_caller_address(validator_address, owner_address());
    validator.add_entry(1, 1, player1(), qualification());
    assert!(
        validator.valid_entry(owner_address(), 1, player1(), qualification()),
        "second entry should still be allowed",
    );
    validator.add_entry(1, 2, player1(), qualification());
    stop_cheat_caller_address(validator_address);

    // Quota exhausted.
    assert!(
        validator.entries_left(owner_address(), 1, player1(), qualification()) == Option::Some(0),
        "quota should be exhausted",
    );
    assert!(
        !validator.valid_entry(owner_address(), 1, player1(), qualification()),
        "no entries left should reject",
    );

    // Removing an entry frees a slot back up.
    start_cheat_caller_address(validator_address, owner_address());
    validator.remove_entry(1, 2, player1(), qualification());
    stop_cheat_caller_address(validator_address);
    assert!(
        validator.entries_left(owner_address(), 1, player1(), qualification()) == Option::Some(1),
        "removing an entry should free a slot",
    );
}

#[test]
fn test_bannable_bans_when_objective_regresses() {
    let validator_address = deploy_adventurer_validator();
    configure_bannable(validator_address, 1, 0);
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    // Still satisfied => not banned.
    set_completed(true);
    assert!(
        !validator.should_ban(owner_address(), 1, 1, player1(), qualification()),
        "satisfied objective should not ban",
    );

    // Objective regressed (e.g. gold dropped below threshold) => ban.
    set_completed(false);
    assert!(
        validator.should_ban(owner_address(), 1, 1, player1(), qualification()),
        "regressed objective should ban",
    );
}

#[test]
fn test_non_bannable_never_bans() {
    let validator_address = deploy_adventurer_validator();
    configure(validator_address, 1, 0); // non-bannable
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    // should_ban short-circuits to false for non-bannable contexts even when the
    // objective is no longer satisfied.
    set_completed(false);
    assert!(
        !validator.should_ban(owner_address(), 1, 1, player1(), qualification()),
        "non-bannable context should never ban",
    );
    stop_mock_call(oracle_address(), selector!("completed_objective"));
}

#[test]
fn test_view_getters() {
    let validator_address = deploy_adventurer_validator();
    configure(validator_address, 5, 3);
    let views = IAdventurerValidatorDispatcher { contract_address: validator_address };

    assert!(views.get_oracle(owner_address(), 5) == oracle_address(), "oracle mismatch");
    assert!(views.get_objective_id(owner_address(), 5) == OBJECTIVE_ID, "objective id mismatch");
    assert!(views.get_entry_limit(owner_address(), 5) == 3, "entry limit mismatch");
}
