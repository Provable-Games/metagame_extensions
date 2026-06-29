//! KYC Registry Validator tests
//!
//! The zk-KYC registry's `get_props` is mocked via `start_mock_call` against the fake
//! registry address stored in config, so the suite is deterministic and needs no fork
//! access or a deployed registry. Policy under test: admit iff `registered && over_18`.

use metagame_extensions_interfaces::entry_requirement_extension::{
    IEntryRequirementExtensionDispatcher, IEntryRequirementExtensionDispatcherTrait,
};
use metagame_extensions_presets::entry_requirement::kyc_registry_validator::Props;
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

fn registry_address() -> ContractAddress {
    0xaaaa.try_into().unwrap()
}

fn deploy_validator() -> IEntryRequirementExtensionDispatcher {
    let contract = declare("KycRegistryValidator").unwrap().contract_class();
    let (addr, _) = contract.deploy(@array![]).unwrap();
    IEntryRequirementExtensionDispatcher { contract_address: addr }
}

fn props(registered: bool, over_18: bool, is_citizen: bool) -> Props {
    Props { registered, over_18, is_citizen, sex: 'M' }
}

/// Mock the registry's `get_props` to return `p` for any account.
fn mock_props(p: Props) {
    start_mock_call(registry_address(), selector!("get_props"), p);
}

/// Config the validator for (owner, context_id) with the given entry limit and bannable.
fn configure(
    validator: IEntryRequirementExtensionDispatcher,
    context_id: u64,
    entry_limit: u32,
    bannable: felt252,
) {
    start_cheat_caller_address(validator.contract_address, owner_address());
    validator
        .add_config(context_id, entry_limit, array![registry_address().into(), bannable].span());
    stop_cheat_caller_address(validator.contract_address);
}

#[test]
fn registered_over18_passes() {
    let v = deploy_validator();
    configure(v, 1, 0, 0);
    mock_props(props(true, true, false)); // citizen flag ignored by policy
    assert(v.valid_entry(owner_address(), 1, player(), array![].span()), 'admit adult KYC');
}

#[test]
fn unregistered_is_rejected() {
    let v = deploy_validator();
    configure(v, 1, 0, 0);
    mock_props(props(false, false, false));
    assert(!v.valid_entry(owner_address(), 1, player(), array![].span()), 'reject unregistered');
}

#[test]
fn registered_under18_is_rejected() {
    let v = deploy_validator();
    configure(v, 1, 0, 0);
    mock_props(props(true, false, true));
    assert(!v.valid_entry(owner_address(), 1, player(), array![].span()), 'reject under-18');
}

#[test]
fn non_empty_qualification_is_rejected() {
    let v = deploy_validator();
    configure(v, 1, 0, 0);
    mock_props(props(true, true, true));
    assert(!v.valid_entry(owner_address(), 1, player(), array![42].span()), 'reject w/ qual data');
}

#[test]
fn quota_exhaustion_rejects() {
    let v = deploy_validator();
    configure(v, 1, 1, 0); // entry_limit = 1
    mock_props(props(true, true, true));

    assert(v.valid_entry(owner_address(), 1, player(), array![].span()), 'first entry ok');
    start_cheat_caller_address(v.contract_address, owner_address());
    v.add_entry(1, 99, player(), array![].span()); // consume the single slot
    stop_cheat_caller_address(v.contract_address);
    assert(!v.valid_entry(owner_address(), 1, player(), array![].span()), 'second blocked');
}

#[test]
fn entries_left_tracks_quota_and_eligibility() {
    let v = deploy_validator();
    configure(v, 1, 3, 0);
    mock_props(props(true, true, true));
    assert(v.entries_left(owner_address(), 1, player(), array![].span()) == Option::Some(3), 'l3');

    start_cheat_caller_address(v.contract_address, owner_address());
    v.add_entry(1, 1, player(), array![].span());
    stop_cheat_caller_address(v.contract_address);
    assert(v.entries_left(owner_address(), 1, player(), array![].span()) == Option::Some(2), 'l2');

    // Not eligible -> zero entries regardless of quota.
    mock_props(props(false, false, false));
    assert(v.entries_left(owner_address(), 1, player(), array![].span()) == Option::Some(0), 'l0');
}

#[test]
fn revoked_kyc_is_bannable_when_configured() {
    let v = deploy_validator();
    configure(v, 1, 0, 1); // bannable = true
    // Registration revoked at the registry -> get_props is now zero.
    mock_props(props(false, false, false));
    assert(v.should_ban(owner_address(), 1, 7, player(), array![].span()), 'ban revoked');
}

#[test]
fn not_bannable_by_default() {
    let v = deploy_validator();
    configure(v, 1, 0, 0); // bannable defaults false
    mock_props(props(false, false, false));
    assert(
        !v.should_ban(owner_address(), 1, 7, player(), array![].span()), 'no ban when !bannable',
    );
}
