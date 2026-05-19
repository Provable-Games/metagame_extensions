// Tests for NFTEntryFee and DynamicEntryFee presets.
//
// Both presets self-validate the host-supplied recipient — NFTEntryFee
// against the host's leaderboard (winner-at-position OR original-payer
// for refunds), DynamicEntryFee against the recipient configured at
// set_entry_fee_config time. Tests stub the host's ILeaderboard +
// IMinigame + game-token via `mock_call`.

use metagame_extensions_interfaces::entry_fee_extension::{
    IEntryFeeExtensionDispatcher, IEntryFeeExtensionDispatcherTrait,
};
use metagame_extensions_presets::entry_fee::dynamic_entry_fee::{
    IDynamicEntryFeeDispatcher, IDynamicEntryFeeDispatcherTrait,
};
use metagame_extensions_presets::entry_fee::nft_entry_fee::{
    INFTEntryFeeDispatcher, INFTEntryFeeDispatcherTrait,
};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, mock_call, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

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
// NFTEntryFee
// ============================================================================

fn deploy_nft_entry_fee() -> ContractAddress {
    let class = declare("nft_entry_fee").unwrap().contract_class();
    let (address, _) = class.deploy(@array![]).unwrap();
    address
}

#[test]
fn test_nft_entry_fee_pay_and_payout_to_winner() {
    let ext_addr = deploy_nft_entry_fee();
    let dispatcher = IEntryFeeExtensionDispatcher { contract_address: ext_addr };
    let view = INFTEntryFeeDispatcher { contract_address: ext_addr };
    let host = host_address();
    let collection = token_address();

    start_cheat_caller_address(ext_addr, host);
    dispatcher.set_entry_fee_config(1, array![collection.into()].span());
    assert!(view.get_collection(host, 1) == collection, "collection not stored");

    // Alice pays at index 0 (token_id=11), Bob at index 1 (token_id=22).
    mock_call(collection, selector!("transfer_from"), (), 10);
    let alice = addr(0xA11CE);
    let bob = addr(0xB0B);
    dispatcher.pay_entry_fee(1, array![alice.into(), 11_u128.into(), 0].span());
    dispatcher.pay_entry_fee(1, array![bob.into(), 22_u128.into(), 0].span());
    stop_cheat_caller_address(ext_addr);

    assert!(view.get_escrowed_payer(host, 1, 0) == alice, "slot 0 payer should be alice");
    assert!(view.get_escrowed_payer(host, 1, 1) == bob, "slot 1 payer should be bob");

    // Stub leaderboard: 2 entries. position 1 wins token 99 owned by carol;
    // position 2 wins token 88 owned by dave.
    mock_call(host, selector!("get_leaderboard_length"), 2_u32, 10);
    let entries = array![
        metagame_extensions_presets::externals::game_components::LeaderboardEntry {
            token_id: 99, score: 10,
        },
        metagame_extensions_presets::externals::game_components::LeaderboardEntry {
            token_id: 88, score: 5,
        },
    ];
    mock_call(host, selector!("get_entries"), entries, 10);
    let game_token = addr(0x6A4E);
    mock_call(host, selector!("token_address"), game_token, 10);
    let carol = addr(0xCA01);
    mock_call(game_token, selector!("owner_of"), carol, 10);

    start_cheat_caller_address(ext_addr, host);
    dispatcher.payout_entry_fee(1, carol, Option::Some(1_u32), array![].span());
    stop_cheat_caller_address(ext_addr);

    assert!(view.is_claimed(host, 1, 0), "slot 0 should be claimed");
}

#[test]
fn test_nft_entry_fee_refunds_to_original_payer_for_unclaimed_position() {
    let ext_addr = deploy_nft_entry_fee();
    let dispatcher = IEntryFeeExtensionDispatcher { contract_address: ext_addr };
    let view = INFTEntryFeeDispatcher { contract_address: ext_addr };
    let host = host_address();
    let collection = token_address();
    let alice = addr(0xA11CE);

    start_cheat_caller_address(ext_addr, host);
    dispatcher.set_entry_fee_config(1, array![collection.into()].span());
    mock_call(collection, selector!("transfer_from"), (), 10);
    dispatcher.pay_entry_fee(1, array![alice.into(), 11_u128.into(), 0].span());

    // Leaderboard is empty -> position 1 has no winner -> refund to original
    // payer (alice, at index 0).
    mock_call(host, selector!("get_leaderboard_length"), 0_u32, 10);
    dispatcher.payout_entry_fee(1, alice, Option::Some(1_u32), array![].span());
    stop_cheat_caller_address(ext_addr);

    assert!(view.is_claimed(host, 1, 0), "slot 0 should be claimed");
}

#[test]
#[should_panic(expected: "NFTEntryFee: recipient does not match expected winner")]
fn test_nft_entry_fee_rejects_wrong_recipient() {
    let ext_addr = deploy_nft_entry_fee();
    let dispatcher = IEntryFeeExtensionDispatcher { contract_address: ext_addr };
    let host = host_address();
    let collection = token_address();
    let alice = addr(0xA11CE);

    start_cheat_caller_address(ext_addr, host);
    dispatcher.set_entry_fee_config(1, array![collection.into()].span());
    mock_call(collection, selector!("transfer_from"), (), 10);
    dispatcher.pay_entry_fee(1, array![alice.into(), 11_u128.into(), 0].span());

    // Refund branch: position 1 with empty leaderboard -> expected = alice.
    // Caller supplies addr(0xBAD) -> extension rejects.
    mock_call(host, selector!("get_leaderboard_length"), 0_u32, 10);
    dispatcher.payout_entry_fee(1, addr(0xBAD), Option::Some(1_u32), array![].span());
}

#[test]
#[should_panic(expected: "NFTEntryFee: already claimed")]
fn test_nft_entry_fee_rejects_double_claim() {
    let ext_addr = deploy_nft_entry_fee();
    let dispatcher = IEntryFeeExtensionDispatcher { contract_address: ext_addr };
    let host = host_address();
    let collection = token_address();
    let alice = addr(0xA11CE);

    start_cheat_caller_address(ext_addr, host);
    dispatcher.set_entry_fee_config(1, array![collection.into()].span());
    mock_call(collection, selector!("transfer_from"), (), 10);
    dispatcher.pay_entry_fee(1, array![alice.into(), 1_u128.into(), 0].span());
    mock_call(host, selector!("get_leaderboard_length"), 0_u32, 10);
    dispatcher.payout_entry_fee(1, alice, Option::Some(1_u32), array![].span());
    dispatcher.payout_entry_fee(1, alice, Option::Some(1_u32), array![].span());
}

#[test]
#[should_panic(expected: "NFTEntryFee: index out of range")]
fn test_nft_entry_fee_rejects_out_of_range_claim() {
    let ext_addr = deploy_nft_entry_fee();
    let dispatcher = IEntryFeeExtensionDispatcher { contract_address: ext_addr };
    let host = host_address();
    start_cheat_caller_address(ext_addr, host);
    dispatcher.set_entry_fee_config(1, array![token_address().into()].span());
    dispatcher.payout_entry_fee(1, addr(0xBBB), Option::Some(1_u32), array![].span());
}

// ============================================================================
// DynamicEntryFee
// ============================================================================

fn deploy_dynamic_entry_fee() -> ContractAddress {
    let class = declare("dynamic_entry_fee").unwrap().contract_class();
    let (address, _) = class.deploy(@array![]).unwrap();
    address
}

#[test]
fn test_dynamic_entry_fee_pricing_and_payout() {
    let ext_addr = deploy_dynamic_entry_fee();
    let dispatcher = IEntryFeeExtensionDispatcher { contract_address: ext_addr };
    let view = IDynamicEntryFeeDispatcher { contract_address: ext_addr };
    let host = host_address();
    let token = token_address();
    let recipient = addr(0xDEFEAD);

    // Config: base = 100, increment = 25, recipient = 0xDEFEAD.
    start_cheat_caller_address(ext_addr, host);
    dispatcher
        .set_entry_fee_config(
            1, array![token.into(), 100_u128.into(), 0, 25_u128.into(), 0, recipient.into()].span(),
        );

    let expected_first: u256 = 100;
    assert!(view.next_fee(host, 1) == expected_first, "first fee should be base");
    assert!(view.get_recipient(host, 1) == recipient, "recipient not stored");

    mock_call(token, selector!("transfer_from"), true, 10);
    dispatcher.pay_entry_fee(1, array![addr(0x1).into()].span());
    dispatcher.pay_entry_fee(1, array![addr(0x2).into()].span());
    dispatcher.pay_entry_fee(1, array![addr(0x3).into()].span());
    stop_cheat_caller_address(ext_addr);

    assert!(view.entry_count(host, 1) == 3, "entry count should be 3");
    let total_expected: u256 = 100 + 125 + 150;
    assert!(view.total_collected(host, 1) == total_expected, "total mismatch");

    // Caller must supply the configured recipient — extension self-validates.
    mock_call(token, selector!("transfer"), true, 10);
    start_cheat_caller_address(ext_addr, host);
    dispatcher.payout_entry_fee(1, recipient, Option::None, array![].span());
    stop_cheat_caller_address(ext_addr);
    assert!(view.is_claimed(host, 1), "should be claimed");
}

#[test]
#[should_panic(expected: "DynamicEntryFee: recipient does not match configured payout address")]
fn test_dynamic_entry_fee_rejects_unauthorized_recipient() {
    let ext_addr = deploy_dynamic_entry_fee();
    let dispatcher = IEntryFeeExtensionDispatcher { contract_address: ext_addr };
    let host = host_address();
    let recipient = addr(0xDEFEAD);
    start_cheat_caller_address(ext_addr, host);
    dispatcher
        .set_entry_fee_config(
            1,
            array![token_address().into(), 100_u128.into(), 0, 25_u128.into(), 0, recipient.into()]
                .span(),
        );
    // Caller tries to drain to a different address than configured -> reject.
    dispatcher.payout_entry_fee(1, addr(0xBAD), Option::None, array![].span());
}

#[test]
#[should_panic(expected: "DynamicEntryFee: already claimed")]
fn test_dynamic_entry_fee_rejects_double_claim() {
    let ext_addr = deploy_dynamic_entry_fee();
    let dispatcher = IEntryFeeExtensionDispatcher { contract_address: ext_addr };
    let host = host_address();
    let recipient = addr(0xDEFEAD);
    start_cheat_caller_address(ext_addr, host);
    dispatcher
        .set_entry_fee_config(
            1,
            array![token_address().into(), 100_u128.into(), 0, 25_u128.into(), 0, recipient.into()]
                .span(),
        );
    mock_call(token_address(), selector!("transfer"), true, 10);
    dispatcher.payout_entry_fee(1, recipient, Option::None, array![].span());
    dispatcher.payout_entry_fee(1, recipient, Option::None, array![].span());
}
