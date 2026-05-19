// Tests for MerklePrize and NFTPrize presets.
//
// Strategy: deploy each preset and drive it through its IPrizeExtension
// trait directly (no host contract). Token interactions (ERC20 transfer,
// ERC721 owner_of / transfer_from) and host callbacks (ILeaderboard,
// IMinigame) are stubbed with `mock_call`. Coverage focuses on the
// preset's own state-machine and validation, not on token semantics.

use core::hash::HashStateTrait;
use core::pedersen::PedersenTrait;
use metagame_extensions_interfaces::prize_extension::{
    IPrizeExtensionDispatcher, IPrizeExtensionDispatcherTrait,
};
use metagame_extensions_presets::prize::merkle_prize::{
    IMerklePrizeDispatcher, IMerklePrizeDispatcherTrait,
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

// Replicate the on-chain leaf-hash derivation from merkle_prize.cairo so the
// test can fabricate a 2-leaf tree and a matching proof.
fn compute_leaf_hash(account: ContractAddress, amount: u256) -> felt252 {
    let amount_low: felt252 = amount.low.into();
    let amount_high: felt252 = amount.high.into();
    let leaf_value = PedersenTrait::new(0)
        .update(account.into())
        .update(amount_low)
        .update(amount_high)
        .update(3)
        .finalize();
    let inner = PedersenTrait::new(0).update(leaf_value).update(1).finalize();
    PedersenTrait::new(0).update(inner).finalize()
}

// OZ commutative pedersen merkle node (sorted): H(0, lo, hi, 2)
fn commutative_hash(a: felt252, b: felt252) -> felt252 {
    let a_u256: u256 = a.into();
    let b_u256: u256 = b.into();
    if a_u256 < b_u256 {
        PedersenTrait::new(0).update(a).update(b).update(2).finalize()
    } else {
        PedersenTrait::new(0).update(b).update(a).update(2).finalize()
    }
}

// ============================================================================
// MerklePrize
// ============================================================================

fn deploy_merkle_prize() -> ContractAddress {
    let class = declare("merkle_prize").unwrap().contract_class();
    let (address, _) = class.deploy(@array![]).unwrap();
    address
}

#[test]
fn test_merkle_prize_add_and_claim_valid_proof() {
    let merkle_prize_addr = deploy_merkle_prize();
    let dispatcher = IPrizeExtensionDispatcher { contract_address: merkle_prize_addr };
    let view = IMerklePrizeDispatcher { contract_address: merkle_prize_addr };

    // Two-leaf tree: (alice, 100), (bob, 50).
    let alice = addr(0xA11CE);
    let bob = addr(0xB0B);
    let alice_amount: u256 = 100;
    let bob_amount: u256 = 50;
    let leaf_alice = compute_leaf_hash(alice, alice_amount);
    let leaf_bob = compute_leaf_hash(bob, bob_amount);
    let root = commutative_hash(leaf_alice, leaf_bob);

    // Host (e.g. budokan) registers the prize.
    let host = host_address();
    start_cheat_caller_address(merkle_prize_addr, host);
    dispatcher.add_prize(1, 1, array![token_address().into(), root].span());
    stop_cheat_caller_address(merkle_prize_addr);

    assert!(view.get_root(host, 1, 1) == root, "root not stored");
    assert!(!view.is_claimed(host, 1, 1, alice), "alice should not be marked claimed yet");

    // Mock the ERC20 payout so we don't need a real token contract.
    mock_call(token_address(), selector!("transfer"), true, 10);

    // Alice claims via the host. Proof for alice = [leaf_bob].
    start_cheat_caller_address(merkle_prize_addr, host);
    dispatcher
        .claim_prize(
            1,
            1, // prize_id
            array![
                alice.into(), // account
                alice_amount.low.into(), alice_amount.high.into(),
                leaf_bob,
            ]
                .span(),
        );
    stop_cheat_caller_address(merkle_prize_addr);

    assert!(view.is_claimed(host, 1, 1, alice), "alice should be marked claimed");
}

#[test]
#[should_panic(expected: "MerklePrize: invalid proof")]
fn test_merkle_prize_rejects_bad_proof() {
    let merkle_prize_addr = deploy_merkle_prize();
    let dispatcher = IPrizeExtensionDispatcher { contract_address: merkle_prize_addr };
    let host = host_address();
    let alice = addr(0xA11CE);
    let alice_amount: u256 = 100;
    let leaf_alice = compute_leaf_hash(alice, alice_amount);
    let root = commutative_hash(leaf_alice, leaf_alice); // arbitrary

    start_cheat_caller_address(merkle_prize_addr, host);
    dispatcher.add_prize(1, 1, array![token_address().into(), root].span());

    // Wrong amount → leaf mismatch → invalid proof.
    let wrong_amount: u256 = 9999;
    dispatcher
        .claim_prize(
            1,
            1,
            array![alice.into(), wrong_amount.low.into(), wrong_amount.high.into(), leaf_alice]
                .span(),
        );
}

#[test]
#[should_panic(expected: "MerklePrize: already claimed")]
fn test_merkle_prize_rejects_double_claim() {
    let merkle_prize_addr = deploy_merkle_prize();
    let dispatcher = IPrizeExtensionDispatcher { contract_address: merkle_prize_addr };
    let host = host_address();

    let alice = addr(0xA11CE);
    let bob = addr(0xB0B);
    let alice_amount: u256 = 100;
    let leaf_alice = compute_leaf_hash(alice, alice_amount);
    let leaf_bob = compute_leaf_hash(bob, 50);
    let root = commutative_hash(leaf_alice, leaf_bob);

    start_cheat_caller_address(merkle_prize_addr, host);
    dispatcher.add_prize(1, 1, array![token_address().into(), root].span());
    mock_call(token_address(), selector!("transfer"), true, 10);
    let claim = array![alice.into(), alice_amount.low.into(), alice_amount.high.into(), leaf_bob]
        .span();
    dispatcher.claim_prize(1, 1, claim);
    dispatcher.claim_prize(1, 1, claim); // second claim → panic
}

#[test]
#[should_panic(expected: "MerklePrize: prize already configured")]
fn test_merkle_prize_blocks_reregistration() {
    let merkle_prize_addr = deploy_merkle_prize();
    let dispatcher = IPrizeExtensionDispatcher { contract_address: merkle_prize_addr };
    start_cheat_caller_address(merkle_prize_addr, host_address());
    dispatcher.add_prize(1, 1, array![token_address().into(), 0x123].span());
    dispatcher.add_prize(1, 1, array![token_address().into(), 0x456].span());
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
fn test_nft_prize_add_and_claim_position() {
    let nft_prize_addr = deploy_nft_prize();
    let dispatcher = IPrizeExtensionDispatcher { contract_address: nft_prize_addr };
    let view = INFTPrizeDispatcher { contract_address: nft_prize_addr };
    let host = host_address();
    let prize_nft = token_address();

    // Pre-transfer model: mock owner_of to return the extension contract.
    mock_call(prize_nft, selector!("owner_of"), nft_prize_addr, 10);

    // Config: one position with token_id = 7
    start_cheat_caller_address(nft_prize_addr, host);
    dispatcher
        .add_prize(
            1, 1, array![prize_nft.into(), host.into(), 1_u32.into(), 7_u128.into(), 0].span(),
        );
    stop_cheat_caller_address(nft_prize_addr);

    assert!(view.get_token_address(host, 1, 1) == prize_nft, "token addr not stored");
    let expected: u256 = 7;
    assert!(view.get_position_token_id(host, 1, 1, 1) == expected, "token id not stored");
    assert!(!view.is_position_claimed(host, 1, 1, 1), "should not be claimed yet");

    // Stub host ILeaderboard to advertise one entry whose token_id = 99.
    let entries = array![
        metagame_extensions_presets::prize::externals::game_components::LeaderboardEntry {
            token_id: 99, score: 1000,
        },
    ];
    mock_call(host, selector!("get_leaderboard_length"), 1_u32, 10);
    mock_call(host, selector!("get_entries"), entries, 10);

    // Stub host IMinigame.token_address → some game token contract.
    let game_token = addr(0x6A4E);
    mock_call(host, selector!("token_address"), game_token, 10);

    // Stub game_token.owner_of(99) → winner.
    let winner = addr(0xFEED);
    mock_call(game_token, selector!("owner_of"), winner, 10);

    // And the final transfer_from on the prize NFT.
    mock_call(prize_nft, selector!("transfer_from"), (), 10);

    start_cheat_caller_address(nft_prize_addr, host);
    dispatcher.claim_prize(1, 1, array![1].span());
    stop_cheat_caller_address(nft_prize_addr);

    assert!(view.is_position_claimed(host, 1, 1, 1), "should be claimed after");
}

#[test]
#[should_panic(expected: "NFTPrize: token must be pre-transferred to extension")]
fn test_nft_prize_rejects_unfunded() {
    let nft_prize_addr = deploy_nft_prize();
    let dispatcher = IPrizeExtensionDispatcher { contract_address: nft_prize_addr };
    let host = host_address();
    let prize_nft = token_address();

    // owner_of returns somebody other than the extension.
    mock_call(prize_nft, selector!("owner_of"), addr(0xDEAD), 10);

    start_cheat_caller_address(nft_prize_addr, host);
    dispatcher
        .add_prize(
            1, 1, array![prize_nft.into(), host.into(), 1_u32.into(), 7_u128.into(), 0].span(),
        );
}

#[test]
#[should_panic(expected: "NFTPrize: position out of range")]
fn test_nft_prize_rejects_out_of_range_position() {
    let nft_prize_addr = deploy_nft_prize();
    let dispatcher = IPrizeExtensionDispatcher { contract_address: nft_prize_addr };
    let host = host_address();
    let prize_nft = token_address();

    mock_call(prize_nft, selector!("owner_of"), nft_prize_addr, 10);

    start_cheat_caller_address(nft_prize_addr, host);
    dispatcher
        .add_prize(
            1, 1, array![prize_nft.into(), host.into(), 1_u32.into(), 7_u128.into(), 0].span(),
        );
    dispatcher.claim_prize(1, 1, array![2].span()); // only 1 position configured
}
