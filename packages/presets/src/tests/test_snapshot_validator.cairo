use metagame_extensions_interfaces::entry_requirement_extension::{
    IEntryRequirementExtensionDispatcher, IEntryRequirementExtensionDispatcherTrait,
};
use metagame_extensions_presets::entry_requirement::snapshot_validator::{
    Entry, ISnapshotValidatorDispatcher, ISnapshotValidatorDispatcherTrait,
};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

fn owner_address() -> ContractAddress {
    0x1234.try_into().unwrap()
}

fn player1() -> ContractAddress {
    0x111.try_into().unwrap()
}

fn deploy_snapshot_validator() -> ContractAddress {
    let contract = declare("SnapshotValidator").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![]).unwrap();
    contract_address
}

fn setup_snapshot_with_entries(validator_address: ContractAddress, entries: Span<Entry>) -> u64 {
    let snapshot = ISnapshotValidatorDispatcher { contract_address: validator_address };
    start_cheat_caller_address(validator_address, owner_address());
    let snapshot_id = snapshot.create_snapshot();
    snapshot.upload_snapshot_data(snapshot_id, entries);
    snapshot.lock_snapshot(snapshot_id);
    stop_cheat_caller_address(validator_address);
    snapshot_id
}

fn configure_context(validator_address: ContractAddress, context_id: u64, snapshot_id: u64) {
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };
    start_cheat_caller_address(validator_address, owner_address());
    validator.add_config(context_id, 0, array![snapshot_id.into()].span());
    stop_cheat_caller_address(validator_address);
}

#[test]
fn test_snapshot_validate_entry_passes_when_quota_available() {
    let validator_address = deploy_snapshot_validator();
    let entries = array![Entry { address: player1(), count: 2 }];
    let snapshot_id = setup_snapshot_with_entries(validator_address, entries.span());
    let context_id: u64 = 1;
    configure_context(validator_address, context_id, snapshot_id);

    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };
    assert!(
        validator.valid_entry(owner_address(), context_id, player1(), array![].span()),
        "First entry should be valid",
    );
}

#[test]
fn test_snapshot_validate_entry_rejects_when_quota_exhausted() {
    // Verifies validate_entry now rejects once used_entries == address_entries (the framework
    // no longer cross-checks entries_left).
    let validator_address = deploy_snapshot_validator();
    let entries = array![Entry { address: player1(), count: 2 }];
    let snapshot_id = setup_snapshot_with_entries(validator_address, entries.span());
    let context_id: u64 = 1;
    configure_context(validator_address, context_id, snapshot_id);

    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    // Burn through the player's quota.
    start_cheat_caller_address(validator_address, owner_address());
    validator.add_entry(context_id, 1, player1(), array![].span());
    validator.add_entry(context_id, 2, player1(), array![].span());
    stop_cheat_caller_address(validator_address);

    assert!(
        !validator.valid_entry(owner_address(), context_id, player1(), array![].span()),
        "validate_entry should reject when quota is exhausted",
    );
}

#[test]
fn test_snapshot_validate_entry_rejects_player_not_in_snapshot() {
    let validator_address = deploy_snapshot_validator();
    let entries = array![Entry { address: player1(), count: 1 }];
    let snapshot_id = setup_snapshot_with_entries(validator_address, entries.span());
    let context_id: u64 = 1;
    configure_context(validator_address, context_id, snapshot_id);

    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    let stranger: ContractAddress = 0xDEAD.try_into().unwrap();
    assert!(
        !validator.valid_entry(owner_address(), context_id, stranger, array![].span()),
        "Player not in snapshot should be rejected",
    );
}
