// Tests for NFTEntryFee and DynamicEntryFee presets.
//
// Both presets are fully sovereign on payout: the host dispatches with a
// `token_id` (or `None` for refund / single-pool flows) and the extension
// resolves the recipient internally. NFTEntryFee derives position via
// `ILeaderboard::get_position` (claim) or reads it from `claim_params[0]`
// (refund). DynamicEntryFee ignores `token_id` and pays the configured
// recipient. Tests stub the host's `ILeaderboard` + `IMinigame` + game
// token via `mock_call`.

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

    // Alice pays at index 0 (escrows NFT 11), Bob at index 1 (escrows NFT 22).
    mock_call(collection, selector!("transfer_from"), (), 10);
    let alice = addr(0xA11CE);
    let bob = addr(0xB0B);
    dispatcher.pay_entry_fee(1, array![alice.into(), 11_u128.into(), 0].span());
    dispatcher.pay_entry_fee(1, array![bob.into(), 22_u128.into(), 0].span());
    stop_cheat_caller_address(ext_addr);

    assert!(view.get_escrowed_payer(host, 1, 0) == alice, "slot 0 payer should be alice");
    assert!(view.get_escrowed_payer(host, 1, 1) == bob, "slot 1 payer should be bob");

    // Claim with token_id=99: leaderboard says it's at position 1, owned by carol.
    mock_call(host, selector!("get_position"), Option::Some(1_u32), 10);
    let game_token = addr(0x6A4E);
    mock_call(host, selector!("token_address"), game_token, 10);
    let carol = addr(0xCA01);
    mock_call(game_token, selector!("owner_of"), carol, 10);

    start_cheat_caller_address(ext_addr, host);
    dispatcher.payout_entry_fee(1, Option::Some(99_felt252), array![].span());
    stop_cheat_caller_address(ext_addr);

    assert!(view.is_claimed(host, 1, 0), "slot 0 should be claimed");
}

#[test]
fn test_nft_entry_fee_refunds_to_original_payer_for_unclaimed_slot() {
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

    // Refund: leaderboard is empty -> slot 1 has no winner -> refund slot 1
    // (escrow index 0) to its original payer (alice).
    mock_call(host, selector!("get_leaderboard_length"), 0_u32, 10);
    dispatcher.payout_entry_fee(1, Option::None, array![1_felt252].span());
    stop_cheat_caller_address(ext_addr);

    assert!(view.is_claimed(host, 1, 0), "slot 0 should be claimed");
}

#[test]
#[should_panic(expected: "NFTEntryFee: slot has a qualifying winner; use the claim path")]
fn test_nft_entry_fee_refund_rejects_when_winner_exists() {
    let ext_addr = deploy_nft_entry_fee();
    let dispatcher = IEntryFeeExtensionDispatcher { contract_address: ext_addr };
    let host = host_address();
    let collection = token_address();
    let alice = addr(0xA11CE);

    start_cheat_caller_address(ext_addr, host);
    dispatcher.set_entry_fee_config(1, array![collection.into()].span());
    mock_call(collection, selector!("transfer_from"), (), 10);
    dispatcher.pay_entry_fee(1, array![alice.into(), 11_u128.into(), 0].span());

    // Leaderboard has 1 winner — refund of slot 1 is invalid (claim path applies).
    mock_call(host, selector!("get_leaderboard_length"), 1_u32, 10);
    dispatcher.payout_entry_fee(1, Option::None, array![1_felt252].span());
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
    dispatcher.payout_entry_fee(1, Option::None, array![1_felt252].span());
    dispatcher.payout_entry_fee(1, Option::None, array![1_felt252].span());
}

#[test]
#[should_panic(expected: "NFTEntryFee: slot_index out of escrow range")]
fn test_nft_entry_fee_rejects_out_of_range_refund() {
    let ext_addr = deploy_nft_entry_fee();
    let dispatcher = IEntryFeeExtensionDispatcher { contract_address: ext_addr };
    let host = host_address();
    start_cheat_caller_address(ext_addr, host);
    dispatcher.set_entry_fee_config(1, array![token_address().into()].span());
    // No payers escrowed yet — slot_index = 1 is out of range.
    dispatcher.payout_entry_fee(1, Option::None, array![1_felt252].span());
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

    // Single-pool payout — extension reads the configured recipient from
    // its own state. token_id + claim_params are ignored.
    mock_call(token, selector!("transfer"), true, 10);
    start_cheat_caller_address(ext_addr, host);
    dispatcher.payout_entry_fee(1, Option::None, array![].span());
    stop_cheat_caller_address(ext_addr);
    assert!(view.is_claimed(host, 1), "should be claimed");
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
    dispatcher.payout_entry_fee(1, Option::None, array![].span());
    dispatcher.payout_entry_fee(1, Option::None, array![].span());
}
