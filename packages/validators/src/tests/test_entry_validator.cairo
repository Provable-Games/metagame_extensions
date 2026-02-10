use budokan_interfaces::entry_validator::{
    IEntryValidatorDispatcher, IEntryValidatorDispatcherTrait,
};
use budokan_test_common::mocks::entry_validator_mock::{
    IEntryValidatorMockDispatcher, IEntryValidatorMockDispatcherTrait,
};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address, start_mock_call,
    stop_cheat_caller_address, stop_mock_call,
};
use starknet::ContractAddress;

// Mock budokan/tournament address used across tests
fn budokan_address() -> ContractAddress {
    0x1234.try_into().unwrap()
}

// Fake ERC721 contract address (no real contract needed)
fn erc721_address() -> ContractAddress {
    0x999.try_into().unwrap()
}

fn deploy_entry_validator() -> ContractAddress {
    let contract = declare("entry_validator_mock").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![budokan_address().into()]).unwrap();
    contract_address
}

fn configure_entry_validator(
    validator_address: ContractAddress,
    tournament_id: u64,
    entry_limit: u8,
    erc721_addr: ContractAddress,
) {
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };
    let mut config = array![erc721_addr.into()];
    // Set caller to budokan address to pass assert_only_budokan check
    start_cheat_caller_address(validator_address, budokan_address());
    validator.add_config(tournament_id, entry_limit, config.span());
    stop_cheat_caller_address(validator_address);
}

fn deploy_open_entry_validator() -> ContractAddress {
    let contract = declare("open_entry_validator_mock").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![budokan_address().into()]).unwrap();
    contract_address
}

fn configure_open_entry_validator(
    validator_address: ContractAddress, tournament_id: u64, entry_limit: u8,
) {
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };
    start_cheat_caller_address(validator_address, budokan_address());
    validator.add_config(tournament_id, entry_limit, array![].span());
    stop_cheat_caller_address(validator_address);
}

#[test]
fn test_valid_entry_with_token_ownership() {
    // Deploy and configure entry validator
    let tournament_id: u64 = 1;
    let entry_validator_address = deploy_entry_validator();
    configure_entry_validator(entry_validator_address, tournament_id, 0, erc721_address());
    let entry_validator = IEntryValidatorDispatcher { contract_address: entry_validator_address };

    // Create a player address
    let player: ContractAddress = 0x123.try_into().unwrap();

    // Mock balance_of to return 1 (player owns a token)
    start_mock_call(erc721_address(), selector!("balance_of"), 1_u256);

    // Test that the player can enter
    let can_enter = entry_validator.valid_entry(tournament_id, player, array![].span());
    assert(can_enter, 'Player with token should enter');
}

#[test]
fn test_invalid_entry_without_token_ownership() {
    // Deploy and configure entry validator
    let tournament_id: u64 = 1;
    let entry_validator_address = deploy_entry_validator();
    configure_entry_validator(entry_validator_address, tournament_id, 0, erc721_address());
    let entry_validator = IEntryValidatorDispatcher { contract_address: entry_validator_address };

    // Create a player address without any tokens
    let player: ContractAddress = 0x456.try_into().unwrap();

    // Mock balance_of to return 0 (player owns no tokens)
    start_mock_call(erc721_address(), selector!("balance_of"), 0_u256);

    // Test that the player cannot enter
    let can_enter = entry_validator.valid_entry(tournament_id, player, array![].span());
    assert(!can_enter, 'No token: cannot enter');
}

#[test]
fn test_valid_entry_with_multiple_tokens() {
    // Deploy and configure entry validator
    let tournament_id: u64 = 1;
    let entry_validator_address = deploy_entry_validator();
    configure_entry_validator(entry_validator_address, tournament_id, 0, erc721_address());
    let entry_validator = IEntryValidatorDispatcher { contract_address: entry_validator_address };

    // Create a player address
    let player: ContractAddress = 0x789.try_into().unwrap();

    // Mock balance_of to return 3 (player owns multiple tokens)
    start_mock_call(erc721_address(), selector!("balance_of"), 3_u256);

    // Test that the player can enter
    let can_enter = entry_validator.valid_entry(tournament_id, player, array![].span());
    assert(can_enter, 'Player with tokens should enter');
}

#[test]
fn test_entry_status_changes_after_transfer() {
    // Deploy and configure entry validator
    let tournament_id: u64 = 1;
    let entry_validator_address = deploy_entry_validator();
    configure_entry_validator(entry_validator_address, tournament_id, 0, erc721_address());
    let entry_validator = IEntryValidatorDispatcher { contract_address: entry_validator_address };

    // Create player addresses
    let player1: ContractAddress = 0xAAA.try_into().unwrap();
    let player2: ContractAddress = 0xBBB.try_into().unwrap();

    // Initially player1 has a token, player2 doesn't
    start_mock_call(erc721_address(), selector!("balance_of"), 1_u256);

    // Verify player1 can enter
    let can_enter = entry_validator.valid_entry(tournament_id, player1, array![].span());
    assert(can_enter, 'Player1 should enter initially');

    // Simulate transfer: player1's balance becomes 0
    stop_mock_call(erc721_address(), selector!("balance_of"));
    start_mock_call(erc721_address(), selector!("balance_of"), 0_u256);

    // Verify player1 can no longer enter (simulating post-transfer)
    let can_enter = entry_validator.valid_entry(tournament_id, player1, array![].span());
    assert(!can_enter, 'Player1 no token after xfer');

    // Now mock player2 having the token
    stop_mock_call(erc721_address(), selector!("balance_of"));
    start_mock_call(erc721_address(), selector!("balance_of"), 1_u256);

    // Verify player2 can now enter
    let can_enter = entry_validator.valid_entry(tournament_id, player2, array![].span());
    assert(can_enter, 'Player2 can enter after xfer');
}

#[test]
fn test_entry_validator_stores_correct_erc721_address() {
    // Deploy and configure entry validator
    let tournament_id: u64 = 1;
    let entry_validator_address = deploy_entry_validator();
    configure_entry_validator(entry_validator_address, tournament_id, 0, erc721_address());
    let entry_validator_mock = IEntryValidatorMockDispatcher {
        contract_address: entry_validator_address,
    };

    // Verify the entry validator stores the correct ERC721 address for this tournament
    let stored_address = entry_validator_mock.get_tournament_erc721_address(tournament_id);
    assert(stored_address == erc721_address(), 'Wrong ERC721 address stored');
}

#[test]
fn test_multiple_players_with_different_ownership() {
    // Deploy and configure entry validator
    let tournament_id: u64 = 1;
    let entry_validator_address = deploy_entry_validator();
    configure_entry_validator(entry_validator_address, tournament_id, 0, erc721_address());
    let entry_validator = IEntryValidatorDispatcher { contract_address: entry_validator_address };

    // Create multiple player addresses
    let player1: ContractAddress = 0x111.try_into().unwrap();
    let player2: ContractAddress = 0x222.try_into().unwrap();
    let player3: ContractAddress = 0x333.try_into().unwrap();

    // Mock balance_of to return 1 (simulates everyone having tokens)
    start_mock_call(erc721_address(), selector!("balance_of"), 1_u256);

    // Test entry validation for player1 and player3 (who have tokens)
    let can_enter_p1 = entry_validator.valid_entry(tournament_id, player1, array![].span());
    assert(can_enter_p1, 'Player1 should enter');

    let can_enter_p3 = entry_validator.valid_entry(tournament_id, player3, array![].span());
    assert(can_enter_p3, 'Player3 should enter');

    // Mock balance_of to return 0 for player2 (no tokens)
    stop_mock_call(erc721_address(), selector!("balance_of"));
    start_mock_call(erc721_address(), selector!("balance_of"), 0_u256);

    let can_enter_p2 = entry_validator.valid_entry(tournament_id, player2, array![].span());
    assert(!can_enter_p2, 'Player2 should not enter');
}

// ========================================
// Open Entry Validator Tests
// ========================================

#[test]
fn test_open_validator_allows_entry_without_tokens() {
    // Deploy open entry validator (no token gating)
    let open_validator_address = deploy_open_entry_validator();
    let open_validator = IEntryValidatorDispatcher { contract_address: open_validator_address };

    // Create a player address without any tokens
    let player: ContractAddress = 0x999.try_into().unwrap();

    // Test that the player can enter even without tokens
    let can_enter = open_validator.valid_entry(0, player, array![].span());
    assert(can_enter, 'Open: player should enter');
}

#[test]
fn test_open_validator_allows_entry_with_tokens() {
    // Deploy open entry validator
    let open_validator_address = deploy_open_entry_validator();
    let open_validator = IEntryValidatorDispatcher { contract_address: open_validator_address };

    // Create a player address
    let player: ContractAddress = 0x888.try_into().unwrap();

    // Test that the player can still enter (tokens don't matter)
    let can_enter = open_validator.valid_entry(0, player, array![].span());
    assert(can_enter, 'Open: player with token enters');
}

#[test]
fn test_open_validator_allows_multiple_players() {
    // Deploy open entry validator
    let open_validator_address = deploy_open_entry_validator();
    let open_validator = IEntryValidatorDispatcher { contract_address: open_validator_address };

    // Create multiple player addresses
    let player1: ContractAddress = 0xAAA.try_into().unwrap();
    let player2: ContractAddress = 0xBBB.try_into().unwrap();
    let player3: ContractAddress = 0xCCC.try_into().unwrap();

    // Test that all players can enter
    let can_enter_p1 = open_validator.valid_entry(0, player1, array![].span());
    assert(can_enter_p1, 'Open: player1 should enter');

    let can_enter_p2 = open_validator.valid_entry(0, player2, array![].span());
    assert(can_enter_p2, 'Open: player2 should enter');

    let can_enter_p3 = open_validator.valid_entry(0, player3, array![].span());
    assert(can_enter_p3, 'Open: player3 should enter');
}

#[test]
fn test_compare_open_vs_token_gated_validators() {
    // Deploy both validators
    let tournament_id: u64 = 1;
    let token_gated_address = deploy_entry_validator();
    configure_entry_validator(token_gated_address, tournament_id, 0, erc721_address());
    let token_gated = IEntryValidatorDispatcher { contract_address: token_gated_address };

    let open_validator_address = deploy_open_entry_validator();
    let open_validator = IEntryValidatorDispatcher { contract_address: open_validator_address };

    // Create two players
    let player_with_token: ContractAddress = 0x111.try_into().unwrap();
    let player_without_token: ContractAddress = 0x222.try_into().unwrap();

    // Test token-gated validator - player with token
    start_mock_call(erc721_address(), selector!("balance_of"), 1_u256);
    let can_enter_gated_with = token_gated
        .valid_entry(tournament_id, player_with_token, array![].span());
    assert(can_enter_gated_with, 'Gated: with token enters');

    // Test token-gated validator - player without token
    stop_mock_call(erc721_address(), selector!("balance_of"));
    start_mock_call(erc721_address(), selector!("balance_of"), 0_u256);
    let can_enter_gated_without = token_gated
        .valid_entry(tournament_id, player_without_token, array![].span());
    assert(!can_enter_gated_without, 'Gated: without token blocked');

    // Test open validator - both should enter
    let can_enter_open_with = open_validator.valid_entry(0, player_with_token, array![].span());
    assert(can_enter_open_with, 'Open: with token enters');

    let can_enter_open_without = open_validator
        .valid_entry(0, player_without_token, array![].span());
    assert(can_enter_open_without, 'Open: without token enters');
}

#[test]
fn test_token_gated_should_ban_after_token_loss() {
    let tournament_id: u64 = 77;
    let validator_address = deploy_entry_validator();
    configure_entry_validator(validator_address, tournament_id, 0, erc721_address());
    let validator = IEntryValidatorDispatcher { contract_address: validator_address };
    let player: ContractAddress = 0xABC.try_into().unwrap();

    start_mock_call(erc721_address(), selector!("balance_of"), 1_u256);
    let should_ban_initial = validator.should_ban(tournament_id, 1, player, array![].span());
    assert(!should_ban_initial, 'Owner should not be banned');

    stop_mock_call(erc721_address(), selector!("balance_of"));
    start_mock_call(erc721_address(), selector!("balance_of"), 0_u256);
    let should_ban_after = validator.should_ban(tournament_id, 1, player, array![].span());
    assert(should_ban_after, 'Non-owner should be banned');
}

#[test]
fn test_open_validator_should_never_ban() {
    let open_validator_address = deploy_open_entry_validator();
    let open_validator = IEntryValidatorDispatcher { contract_address: open_validator_address };
    let player: ContractAddress = 0xDDD.try_into().unwrap();

    let should_ban = open_validator.should_ban(0, 1, player, array![].span());
    assert(!should_ban, 'Open validator should never ban');
}

#[test]
fn test_open_validator_entries_left_and_remove_tracking() {
    let tournament_id: u64 = 5;
    let player: ContractAddress = 0xEEE.try_into().unwrap();
    let open_validator_address = deploy_open_entry_validator();
    let open_validator = IEntryValidatorDispatcher { contract_address: open_validator_address };

    configure_open_entry_validator(open_validator_address, tournament_id, 2);

    let initial = open_validator.entries_left(tournament_id, player, array![].span());
    assert(initial.is_some(), 'Should have limited entries');
    assert(initial.unwrap() == 2, 'Should start with 2 entries');

    start_cheat_caller_address(open_validator_address, budokan_address());
    open_validator.add_entry(tournament_id, 0, player, array![].span());
    open_validator.add_entry(tournament_id, 0, player, array![].span());
    stop_cheat_caller_address(open_validator_address);

    let after_add = open_validator.entries_left(tournament_id, player, array![].span());
    assert(after_add.unwrap() == 0, 'after add');

    start_cheat_caller_address(open_validator_address, budokan_address());
    open_validator.remove_entry(tournament_id, 0, player, array![].span());
    stop_cheat_caller_address(open_validator_address);

    let after_remove = open_validator.entries_left(tournament_id, player, array![].span());
    assert(after_remove.unwrap() == 1, 'after rm');

    start_cheat_caller_address(open_validator_address, budokan_address());
    open_validator.remove_entry(tournament_id, 0, player, array![].span());
    open_validator.remove_entry(tournament_id, 0, player, array![].span());
    stop_cheat_caller_address(open_validator_address);

    let final_left = open_validator.entries_left(tournament_id, player, array![].span());
    assert(final_left.unwrap() == 2, 'rm noop');
}
