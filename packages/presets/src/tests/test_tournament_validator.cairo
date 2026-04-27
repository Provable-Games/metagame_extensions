//! Tournament Validator tests
//!
//! Focused on the new quota-in-validate_entry behavior. Cross-contract dispatches
//! (ITournament / IRegistration / IMinigame / IERC721) are mocked via `start_mock_call`
//! so we can exercise both the happy path and the quota-exhausted path without
//! standing up a real tournament contract.

use metagame_extensions_interfaces::entry_requirement_extension::{
    IEntryRequirementExtensionDispatcher, IEntryRequirementExtensionDispatcherTrait,
};
use metagame_extensions_interfaces::registration::Registration;
use metagame_extensions_interfaces::tournament::{
    EntryFee, GameConfig, Metadata, Period, Schedule, Tournament,
};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address, start_mock_call,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

const QUALIFIER_TYPE_PARTICIPANTS: felt252 = 0;
const QUALIFYING_MODE_PER_TOKEN: felt252 = 0;

fn tournament_address() -> ContractAddress {
    0xABCD.try_into().unwrap()
}

fn game_address() -> ContractAddress {
    0xBEEF.try_into().unwrap()
}

fn game_token_address() -> ContractAddress {
    0xCAFE.try_into().unwrap()
}

fn player1() -> ContractAddress {
    0x111.try_into().unwrap()
}

fn deploy_tournament_validator() -> ContractAddress {
    let contract = declare("TournamentValidator").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![]).unwrap();
    contract_address
}

/// Build a minimal Tournament struct. Only `game_config.address` is consulted by
/// `validate_token_participation`; everything else is filler that satisfies serde.
fn fake_tournament(id: u64) -> Tournament {
    Tournament {
        id,
        created_at: 0,
        created_by: 0_felt252.try_into().unwrap(),
        creator_token_id: 0,
        metadata: Metadata { name: 'fake', description: "" },
        schedule: Schedule {
            registration: Option::None, game: Period { start: 0, end: 0 }, submission_duration: 0,
        },
        game_config: GameConfig {
            address: game_address(), settings_id: 0, soulbound: false, play_url: "",
        },
        entry_fee: Option::<EntryFee>::None,
        entry_requirement: Option::None,
    }
}

fn fake_registration(token_id: u64, context_id: u64) -> Registration {
    Registration {
        game_address: game_address(),
        game_token_id: token_id,
        context_id,
        entry_number: 1,
        has_submitted: false,
        is_banned: false,
    }
}

fn configure_per_token_participants(
    validator_address: ContractAddress,
    qualifying_tournament_id: u64,
    target_tournament_id: u64,
    entry_limit: u32,
) {
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };
    // config[0]: qualifier_type (PARTICIPANTS)
    // config[1]: qualifying_mode (PER_TOKEN)
    // config[2]: top_positions (unused for PARTICIPANTS)
    // config[3..]: qualifying tournament IDs
    let config = array![
        QUALIFIER_TYPE_PARTICIPANTS, QUALIFYING_MODE_PER_TOKEN, 0, qualifying_tournament_id.into(),
    ];
    // The context_owner namespace is the caller of add_config — same address used by
    // validate_entry_internal as the tournament dispatcher target.
    start_cheat_caller_address(validator_address, tournament_address());
    validator.add_config(target_tournament_id, entry_limit, config.span());
    stop_cheat_caller_address(validator_address);
}

/// Mock all four cross-contract reads on the happy PARTICIPANTS path.
fn mock_happy_participants_path(qualifying_tournament_id: u64, qualifying_token_id: u64) {
    start_mock_call(
        tournament_address(), selector!("tournament"), fake_tournament(qualifying_tournament_id),
    );
    start_mock_call(
        tournament_address(),
        selector!("get_registration"),
        fake_registration(qualifying_token_id, qualifying_tournament_id),
    );
    start_mock_call(game_address(), selector!("token_address"), game_token_address());
    start_mock_call(game_token_address(), selector!("owner_of"), player1());
}

#[test]
fn test_per_token_first_entry_passes() {
    let validator_address = deploy_tournament_validator();
    let qualifying_id: u64 = 7;
    let target_id: u64 = 8;
    let qualifying_token_id: u64 = 42;
    configure_per_token_participants(validator_address, qualifying_id, target_id, 3);
    mock_happy_participants_path(qualifying_id, qualifying_token_id);

    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };
    let qualification = array![qualifying_id.into(), qualifying_token_id.into()];

    assert!(
        validator.valid_entry(tournament_address(), target_id, player1(), qualification.span()),
        "first entry under quota should pass",
    );
}

#[test]
fn test_per_token_quota_exhausted_rejects() {
    // Verifies the new validate_entry quota check rejects once token_entries == entry_limit
    // (the framework no longer cross-checks entries_left).
    let validator_address = deploy_tournament_validator();
    let qualifying_id: u64 = 7;
    let target_id: u64 = 8;
    let qualifying_token_id: u64 = 42;
    let entry_limit: u32 = 2;
    configure_per_token_participants(validator_address, qualifying_id, target_id, entry_limit);
    mock_happy_participants_path(qualifying_id, qualifying_token_id);

    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };
    let qualification = array![qualifying_id.into(), qualifying_token_id.into()];

    // Burn through the per-token quota.
    start_cheat_caller_address(validator_address, tournament_address());
    let mut i: u64 = 0;
    while i < entry_limit.into() {
        validator.add_entry(target_id, (i + 1).into(), player1(), qualification.span());
        i += 1;
    }
    stop_cheat_caller_address(validator_address);

    assert!(
        !validator.valid_entry(tournament_address(), target_id, player1(), qualification.span()),
        "validate_entry should reject once per-token quota is exhausted",
    );
}

#[test]
fn test_per_token_unlimited_when_entry_limit_zero() {
    let validator_address = deploy_tournament_validator();
    let qualifying_id: u64 = 7;
    let target_id: u64 = 8;
    let qualifying_token_id: u64 = 42;
    // entry_limit = 0 → unlimited
    configure_per_token_participants(validator_address, qualifying_id, target_id, 0);
    mock_happy_participants_path(qualifying_id, qualifying_token_id);

    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };
    let qualification = array![qualifying_id.into(), qualifying_token_id.into()];

    // Add many entries — should still pass since limit is unbounded.
    start_cheat_caller_address(validator_address, tournament_address());
    let mut i: u64 = 0;
    while i < 5 {
        validator.add_entry(target_id, (i + 1).into(), player1(), qualification.span());
        i += 1;
    }
    stop_cheat_caller_address(validator_address);

    assert!(
        validator.valid_entry(tournament_address(), target_id, player1(), qualification.span()),
        "unlimited entry_limit should never reject on quota grounds",
    );
}

#[test]
fn test_invalid_qualification_rejects_before_quota_check() {
    // Sanity: the quota check is the *second* gate — eligibility (valid qualification) still
    // matters. Wrong qualifying tournament id → validate_entry_internal fails first.
    let validator_address = deploy_tournament_validator();
    let qualifying_id: u64 = 7;
    let target_id: u64 = 8;
    configure_per_token_participants(validator_address, qualifying_id, target_id, 3);

    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };
    let unrelated_id: u64 = 999; // not in the qualifying set
    let qualification = array![unrelated_id.into(), 42_u64.into()];

    assert!(
        !validator.valid_entry(tournament_address(), target_id, player1(), qualification.span()),
        "qualification referencing non-qualifying tournament must be rejected",
    );
}
