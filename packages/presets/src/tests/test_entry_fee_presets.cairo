// Tests for NFTEntryFee and DynamicEntryFee presets.

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
fn test_nft_entry_fee_pay_and_claim() {
    let ext_addr = deploy_nft_entry_fee();
    let dispatcher = IEntryFeeExtensionDispatcher { contract_address: ext_addr };
    let view = INFTEntryFeeDispatcher { contract_address: ext_addr };
    let host = host_address();
    let collection = token_address();

    start_cheat_caller_address(ext_addr, host);
    dispatcher.set_entry_fee_config(1, array![collection.into()].span());

    assert!(view.get_collection(host, 1) == collection, "collection not stored");
    assert!(view.get_escrowed_count(host, 1) == 0, "count should start at 0");

    // Two players pay with token ids 11 and 22.
    mock_call(collection, selector!("transfer_from"), (), 10);
    let alice = addr(0xA11CE);
    let bob = addr(0xB0B);
    dispatcher.pay_entry_fee(1, array![alice.into(), 11_u128.into(), 0].span());
    dispatcher.pay_entry_fee(1, array![bob.into(), 22_u128.into(), 0].span());
    stop_cheat_caller_address(ext_addr);

    assert!(view.get_escrowed_count(host, 1) == 2, "count should be 2");
    let id0: u256 = 11;
    let id1: u256 = 22;
    assert!(view.get_escrowed_token_id(host, 1, 0) == id0, "slot 0 mismatch");
    assert!(view.get_escrowed_token_id(host, 1, 1) == id1, "slot 1 mismatch");

    // Host claims both into different recipients.
    start_cheat_caller_address(ext_addr, host);
    dispatcher.payout_entry_fee(1, alice, Option::Some(1_u32), array![].span());
    dispatcher.payout_entry_fee(1, bob, Option::Some(2_u32), array![].span());
    stop_cheat_caller_address(ext_addr);

    assert!(view.is_claimed(host, 1, 0), "slot 0 should be claimed");
    assert!(view.is_claimed(host, 1, 1), "slot 1 should be claimed");
}

#[test]
#[should_panic(expected: "NFTEntryFee: already claimed")]
fn test_nft_entry_fee_rejects_double_claim() {
    let ext_addr = deploy_nft_entry_fee();
    let dispatcher = IEntryFeeExtensionDispatcher { contract_address: ext_addr };
    let host = host_address();
    let collection = token_address();

    start_cheat_caller_address(ext_addr, host);
    dispatcher.set_entry_fee_config(1, array![collection.into()].span());
    mock_call(collection, selector!("transfer_from"), (), 10);
    dispatcher.pay_entry_fee(1, array![addr(0xAAA).into(), 1_u128.into(), 0].span());
    dispatcher.payout_entry_fee(1, addr(0xBBB), Option::Some(1_u32), array![].span());
    dispatcher.payout_entry_fee(1, addr(0xBBB), Option::Some(1_u32), array![].span());
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
fn test_dynamic_entry_fee_pricing_and_claim() {
    let ext_addr = deploy_dynamic_entry_fee();
    let dispatcher = IEntryFeeExtensionDispatcher { contract_address: ext_addr };
    let view = IDynamicEntryFeeDispatcher { contract_address: ext_addr };
    let host = host_address();
    let token = token_address();

    // base = 100, increment = 25 → fees: 100, 125, 150
    start_cheat_caller_address(ext_addr, host);
    dispatcher
        .set_entry_fee_config(
            1,
            array![token.into(), 100_u128.into(), 0, // base
            25_u128.into(), 0 // increment
            ].span(),
        );

    let expected_first: u256 = 100;
    assert!(view.next_fee(host, 1) == expected_first, "first fee should be base");

    mock_call(token, selector!("transfer_from"), true, 10);
    dispatcher.pay_entry_fee(1, array![addr(0x1).into()].span());
    dispatcher.pay_entry_fee(1, array![addr(0x2).into()].span());
    dispatcher.pay_entry_fee(1, array![addr(0x3).into()].span());
    stop_cheat_caller_address(ext_addr);

    assert!(view.entry_count(host, 1) == 3, "entry count should be 3");
    let total_expected: u256 = 100 + 125 + 150;
    assert!(view.total_collected(host, 1) == total_expected, "total mismatch");
    let next_expected: u256 = 175;
    assert!(view.next_fee(host, 1) == next_expected, "fourth fee should be 175");

    // Claim drains pool to recipient.
    mock_call(token, selector!("transfer"), true, 10);
    let recipient = addr(0xDEFEAD);
    start_cheat_caller_address(ext_addr, host);
    dispatcher.payout_entry_fee(1, recipient, Option::None, array![].span());
    stop_cheat_caller_address(ext_addr);
    assert!(view.is_claimed(host, 1), "should be claimed");
}

#[test]
#[should_panic(expected: "DynamicEntryFee: already claimed")]
fn test_dynamic_entry_fee_rejects_double_claim() {
    let ext_addr = deploy_dynamic_entry_fee();
    let dispatcher = IEntryFeeExtensionDispatcher { contract_address: ext_addr };
    let host = host_address();
    start_cheat_caller_address(ext_addr, host);
    dispatcher
        .set_entry_fee_config(
            1, array![token_address().into(), 100_u128.into(), 0, 25_u128.into(), 0].span(),
        );
    mock_call(token_address(), selector!("transfer"), true, 10);
    dispatcher.payout_entry_fee(1, addr(0x1), Option::None, array![].span());
    dispatcher.payout_entry_fee(1, addr(0x1), Option::None, array![].span());
}
