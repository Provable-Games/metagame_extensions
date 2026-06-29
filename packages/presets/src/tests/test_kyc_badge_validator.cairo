//! KYC Badge Validator tests
//!
//! The badge contract's `is_member(account, campaign)` is mocked via
//! `start_mock_call` against the fake badge address stored in config, so the suite
//! is deterministic and needs no deployed badge contract. Policy: admit iff the
//! account holds the configured campaign membership.

use metagame_extensions_interfaces::entry_requirement_extension::{
    IEntryRequirementExtensionDispatcher, IEntryRequirementExtensionDispatcherTrait,
};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address, start_mock_call,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

fn owner_address() -> ContractAddress {
    0x1234.try_into().unwrap()
}

fn player() -> ContractAddress {
    0x111.try_into().unwrap()
}

fn badge_address() -> ContractAddress {
    0xbbbb.try_into().unwrap()
}

fn deploy_validator() -> IEntryRequirementExtensionDispatcher {
    let contract = declare("KycBadgeValidator").unwrap().contract_class();
    let (addr, _) = contract.deploy(@array![]).unwrap();
    IEntryRequirementExtensionDispatcher { contract_address: addr }
}

/// Mock the badge's `has_badge` to return `member` for any account.
fn mock_member(member: bool) {
    start_mock_call(badge_address(), selector!("has_badge"), member);
}

fn configure(
    validator: IEntryRequirementExtensionDispatcher,
    context_id: u64,
    entry_limit: u32,
    bannable: felt252,
) {
    start_cheat_caller_address(validator.contract_address, owner_address());
    validator.add_config(context_id, entry_limit, array![badge_address().into(), bannable].span());
    stop_cheat_caller_address(validator.contract_address);
}

#[test]
fn member_passes() {
    let v = deploy_validator();
    configure(v, 1, 0, 0);
    mock_member(true);
    assert(v.valid_entry(owner_address(), 1, player(), array![].span()), 'admit member');
}

#[test]
fn non_member_is_rejected() {
    let v = deploy_validator();
    configure(v, 1, 0, 0);
    mock_member(false);
    assert(!v.valid_entry(owner_address(), 1, player(), array![].span()), 'reject non-member');
}

#[test]
fn non_empty_qualification_is_rejected() {
    let v = deploy_validator();
    configure(v, 1, 0, 0);
    mock_member(true);
    assert(!v.valid_entry(owner_address(), 1, player(), array![7].span()), 'reject w/ qual data');
}

#[test]
fn quota_exhaustion_rejects() {
    let v = deploy_validator();
    configure(v, 1, 1, 0);
    mock_member(true);
    assert(v.valid_entry(owner_address(), 1, player(), array![].span()), 'first entry ok');
    start_cheat_caller_address(v.contract_address, owner_address());
    v.add_entry(1, 99, player(), array![].span());
    stop_cheat_caller_address(v.contract_address);
    assert(!v.valid_entry(owner_address(), 1, player(), array![].span()), 'second blocked');
}

#[test]
fn entries_left_tracks_quota_and_membership() {
    let v = deploy_validator();
    configure(v, 1, 3, 0);
    mock_member(true);
    assert(v.entries_left(owner_address(), 1, player(), array![].span()) == Option::Some(3), 'l3');
    start_cheat_caller_address(v.contract_address, owner_address());
    v.add_entry(1, 1, player(), array![].span());
    stop_cheat_caller_address(v.contract_address);
    assert(v.entries_left(owner_address(), 1, player(), array![].span()) == Option::Some(2), 'l2');

    mock_member(false);
    assert(v.entries_left(owner_address(), 1, player(), array![].span()) == Option::Some(0), 'l0');
}

#[test]
fn lost_badge_is_bannable_when_configured() {
    let v = deploy_validator();
    configure(v, 1, 0, 1); // bannable
    mock_member(false); // badge no longer held
    assert(v.should_ban(owner_address(), 1, 7, player(), array![].span()), 'ban lost badge');
}

#[test]
fn not_bannable_by_default() {
    let v = deploy_validator();
    configure(v, 1, 0, 0);
    mock_member(false);
    assert(
        !v.should_ban(owner_address(), 1, 7, player(), array![].span()), 'no ban when !bannable',
    );
}
