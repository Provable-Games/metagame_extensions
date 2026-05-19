// Tests for the NFTPrize preset.
//
// Strategy: deploy the preset and drive it through its IPrizeExtension
// trait directly (no host contract). Token interactions (ERC721
// owner_of / transfer_from) and host callbacks (ILeaderboard, IMinigame)
// are stubbed with `mock_call`. NFTPrize self-validates: callers can't
// redirect payouts — the extension queries the host's leaderboard to
// determine the canonical recipient and asserts the host-supplied one
// matches.

use metagame_extensions_interfaces::prize_extension::{
    IPrizeExtensionDispatcher, IPrizeExtensionDispatcherTrait,
};
use metagame_extensions_presets::prize::nft_prize::{INFTPrizeDispatcher, INFTPrizeDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, mock_call, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

// ============================================================================
// Helpers
// ============================================================================

fn host_address() -> ContractAddress {
    0xBEEF.try_into().unwrap()
}

fn token_address() -> ContractAddress {
    0xCAFE.try_into().unwrap()
}

fn addr(value: felt252) -> ContractAddress {
    value.try_into().unwrap()
}

// ============================================================================
// NFTPrize
// ============================================================================

fn deploy_nft_prize() -> ContractAddress {
    let class = declare("nft_prize").unwrap().contract_class();
    let (address, _) = class.deploy(@array![]).unwrap();
    address
}

#[test]
fn test_nft_prize_add_and_payout_position_to_winner() {
    let nft_prize_addr = deploy_nft_prize();
    let dispatcher = IPrizeExtensionDispatcher { contract_address: nft_prize_addr };
    let view = INFTPrizeDispatcher { contract_address: nft_prize_addr };
    let host = host_address();
    let prize_nft = token_address();
    let sponsor = addr(0x5b0b);

    // Pre-transfer model: mock owner_of to return the extension contract.
    mock_call(prize_nft, selector!("owner_of"), nft_prize_addr, 10);

    // Config: [token, sponsor, num_positions=1, token_id=7]
    start_cheat_caller_address(nft_prize_addr, host);
    dispatcher
        .add_prize(
            1, 1, array![prize_nft.into(), sponsor.into(), 1_u32.into(), 7_u128.into(), 0].span(),
        );
    stop_cheat_caller_address(nft_prize_addr);

    assert!(view.get_token_address(host, 1, 1) == prize_nft, "token addr not stored");
    assert!(view.get_sponsor(host, 1, 1) == sponsor, "sponsor not stored");

    // Stub host: leaderboard length 1, winner token_id 99.
    mock_call(host, selector!("get_leaderboard_length"), 1_u32, 10);
    let entries = array![
        metagame_extensions_presets::prize::externals::game_components::LeaderboardEntry {
            token_id: 99, score: 1000,
        },
    ];
    mock_call(host, selector!("get_entries"), entries, 10);
    let game_token = addr(0x6A4E);
    mock_call(host, selector!("token_address"), game_token, 10);
    let winner = addr(0xFEED);
    mock_call(game_token, selector!("owner_of"), winner, 10);
    mock_call(prize_nft, selector!("transfer_from"), (), 10);

    // Caller supplies the correct recipient (winner) — extension validates.
    start_cheat_caller_address(nft_prize_addr, host);
    dispatcher.payout_prize(1, 1, Option::Some(1_u32), winner, array![].span());
    stop_cheat_caller_address(nft_prize_addr);

    assert!(view.is_position_claimed(host, 1, 1, 1), "should be claimed after");
}

#[test]
fn test_nft_prize_payout_to_sponsor_for_unclaimed_position() {
    let nft_prize_addr = deploy_nft_prize();
    let dispatcher = IPrizeExtensionDispatcher { contract_address: nft_prize_addr };
    let view = INFTPrizeDispatcher { contract_address: nft_prize_addr };
    let host = host_address();
    let prize_nft = token_address();
    let sponsor = addr(0x5b0b);

    mock_call(prize_nft, selector!("owner_of"), nft_prize_addr, 10);

    start_cheat_caller_address(nft_prize_addr, host);
    dispatcher
        .add_prize(
            1, 1, array![prize_nft.into(), sponsor.into(), 1_u32.into(), 7_u128.into(), 0].span(),
        );

    // Leaderboard has zero entries -> refund path: expected recipient = sponsor.
    mock_call(host, selector!("get_leaderboard_length"), 0_u32, 10);
    mock_call(prize_nft, selector!("transfer_from"), (), 10);
    dispatcher.payout_prize(1, 1, Option::Some(1_u32), sponsor, array![].span());
    stop_cheat_caller_address(nft_prize_addr);

    assert!(view.is_position_claimed(host, 1, 1, 1), "position should be marked claimed");
}

#[test]
#[should_panic(expected: "NFTPrize: recipient does not match expected winner")]
fn test_nft_prize_rejects_wrong_recipient() {
    let nft_prize_addr = deploy_nft_prize();
    let dispatcher = IPrizeExtensionDispatcher { contract_address: nft_prize_addr };
    let host = host_address();
    let prize_nft = token_address();
    let sponsor = addr(0x5b0b);

    mock_call(prize_nft, selector!("owner_of"), nft_prize_addr, 10);

    start_cheat_caller_address(nft_prize_addr, host);
    dispatcher
        .add_prize(
            1, 1, array![prize_nft.into(), sponsor.into(), 1_u32.into(), 7_u128.into(), 0].span(),
        );

    // Leaderboard length 1, winner is addr(0xFEED). Caller supplies addr(0xBAD)
    // -> extension rejects.
    mock_call(host, selector!("get_leaderboard_length"), 1_u32, 10);
    let entries = array![
        metagame_extensions_presets::prize::externals::game_components::LeaderboardEntry {
            token_id: 99, score: 1000,
        },
    ];
    mock_call(host, selector!("get_entries"), entries, 10);
    let game_token = addr(0x6A4E);
    mock_call(host, selector!("token_address"), game_token, 10);
    mock_call(game_token, selector!("owner_of"), addr(0xFEED), 10);

    dispatcher.payout_prize(1, 1, Option::Some(1_u32), addr(0xBAD), array![].span());
}

#[test]
#[should_panic(expected: "NFTPrize: token must be pre-transferred to extension")]
fn test_nft_prize_rejects_unfunded() {
    let nft_prize_addr = deploy_nft_prize();
    let dispatcher = IPrizeExtensionDispatcher { contract_address: nft_prize_addr };
    let host = host_address();
    let prize_nft = token_address();
    let sponsor = addr(0x5b0b);

    // owner_of returns somebody other than the extension.
    mock_call(prize_nft, selector!("owner_of"), addr(0xDEAD), 10);

    start_cheat_caller_address(nft_prize_addr, host);
    dispatcher
        .add_prize(
            1, 1, array![prize_nft.into(), sponsor.into(), 1_u32.into(), 7_u128.into(), 0].span(),
        );
}

#[test]
#[should_panic(expected: "NFTPrize: position out of range")]
fn test_nft_prize_rejects_out_of_range_position() {
    let nft_prize_addr = deploy_nft_prize();
    let dispatcher = IPrizeExtensionDispatcher { contract_address: nft_prize_addr };
    let host = host_address();
    let prize_nft = token_address();
    let sponsor = addr(0x5b0b);

    mock_call(prize_nft, selector!("owner_of"), nft_prize_addr, 10);

    start_cheat_caller_address(nft_prize_addr, host);
    dispatcher
        .add_prize(
            1, 1, array![prize_nft.into(), sponsor.into(), 1_u32.into(), 7_u128.into(), 0].span(),
        );
    dispatcher.payout_prize(1, 1, Option::Some(2_u32), addr(0xFEED), array![].span());
}

#[test]
#[should_panic(expected: "NFTPrize: position already claimed")]
fn test_nft_prize_rejects_double_payout() {
    let nft_prize_addr = deploy_nft_prize();
    let dispatcher = IPrizeExtensionDispatcher { contract_address: nft_prize_addr };
    let host = host_address();
    let prize_nft = token_address();
    let sponsor = addr(0x5b0b);

    mock_call(prize_nft, selector!("owner_of"), nft_prize_addr, 10);

    start_cheat_caller_address(nft_prize_addr, host);
    dispatcher
        .add_prize(
            1, 1, array![prize_nft.into(), sponsor.into(), 1_u32.into(), 7_u128.into(), 0].span(),
        );

    // Refund path twice -> second call rejected by "already claimed".
    mock_call(host, selector!("get_leaderboard_length"), 0_u32, 10);
    mock_call(prize_nft, selector!("transfer_from"), (), 10);
    dispatcher.payout_prize(1, 1, Option::Some(1_u32), sponsor, array![].span());
    dispatcher.payout_prize(1, 1, Option::Some(1_u32), sponsor, array![].span());
}
