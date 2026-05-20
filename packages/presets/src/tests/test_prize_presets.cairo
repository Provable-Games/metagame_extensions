// Tests for the NFTPrize preset.
//
// Strategy: deploy the preset and drive it through its IPrizeExtension
// trait directly (no host contract). Token interactions (ERC721
// owner_of / transfer_from) and host callbacks (ILeaderboard, IMinigame)
// are stubbed with `mock_call`. NFTPrize is fully sovereign: the host
// dispatches with `token_id` (claim) or `None` + slot_index in
// payout_params (refund); the extension resolves position and recipient
// from its own state and the host's leaderboard.

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
fn test_nft_prize_add_and_payout_to_winner() {
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

    // Stub host: game token at position 1 is claimant_token=99, owned by
    // winner. Refund branch unreachable since position resolves directly
    // from get_position.
    mock_call(host, selector!("get_position"), Option::Some(1_u32), 10);
    let game_token = addr(0x6A4E);
    mock_call(host, selector!("token_address"), game_token, 10);
    let winner = addr(0xFEED);
    mock_call(game_token, selector!("owner_of"), winner, 10);
    mock_call(prize_nft, selector!("transfer_from"), (), 10);

    start_cheat_caller_address(nft_prize_addr, host);
    dispatcher.payout_prize(1, 1, Option::Some(99_felt252), array![].span());
    stop_cheat_caller_address(nft_prize_addr);

    assert!(view.is_position_claimed(host, 1, 1, 1), "should be claimed after");
}

#[test]
fn test_nft_prize_refund_to_sponsor_for_unclaimed_position() {
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

    // Refund path: leaderboard has 0 entries — slot 1 is unwon. Sponsor
    // gets the NFT back. token_id=None signals refund; payout_params=[1]
    // selects slot 1.
    mock_call(host, selector!("get_leaderboard_length"), 0_u32, 10);
    mock_call(prize_nft, selector!("transfer_from"), (), 10);
    dispatcher.payout_prize(1, 1, Option::None, array![1_felt252].span());
    stop_cheat_caller_address(nft_prize_addr);

    assert!(view.is_position_claimed(host, 1, 1, 1), "position should be marked claimed");
}

#[test]
#[should_panic(expected: "NFTPrize: slot has a qualifying winner; use the claim path")]
fn test_nft_prize_refund_rejects_when_winner_exists() {
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

    // Leaderboard has 1 qualifying winner — refund of slot 1 is invalid
    // (claim path applies).
    mock_call(host, selector!("get_leaderboard_length"), 1_u32, 10);
    dispatcher.payout_prize(1, 1, Option::None, array![1_felt252].span());
}

#[test]
#[should_panic(expected: "NFTPrize: token not on leaderboard")]
fn test_nft_prize_claim_rejects_token_not_on_leaderboard() {
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

    // Token isn't ranked.
    mock_call(host, selector!("get_position"), Option::<u32>::None, 10);
    dispatcher.payout_prize(1, 1, Option::Some(99_felt252), array![].span());
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
#[should_panic(expected: "NFTPrize: position out of prize range")]
fn test_nft_prize_claim_rejects_position_beyond_prize_range() {
    let nft_prize_addr = deploy_nft_prize();
    let dispatcher = IPrizeExtensionDispatcher { contract_address: nft_prize_addr };
    let host = host_address();
    let prize_nft = token_address();
    let sponsor = addr(0x5b0b);

    mock_call(prize_nft, selector!("owner_of"), nft_prize_addr, 10);

    // Only 1 position configured.
    start_cheat_caller_address(nft_prize_addr, host);
    dispatcher
        .add_prize(
            1, 1, array![prize_nft.into(), sponsor.into(), 1_u32.into(), 7_u128.into(), 0].span(),
        );

    // Token's position is 2, but only 1 prize position exists.
    mock_call(host, selector!("get_position"), Option::Some(2_u32), 10);
    dispatcher.payout_prize(1, 1, Option::Some(99_felt252), array![].span());
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
    dispatcher.payout_prize(1, 1, Option::None, array![1_felt252].span());
    dispatcher.payout_prize(1, 1, Option::None, array![1_felt252].span());
}
