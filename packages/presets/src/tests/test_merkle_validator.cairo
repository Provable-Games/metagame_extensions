use core::hash::HashStateTrait;
use core::pedersen::PedersenTrait;
use metagame_extensions_interfaces::entry_requirement_extension::{
    IEntryRequirementExtensionDispatcher, IEntryRequirementExtensionDispatcherTrait,
};
use metagame_extensions_presets::entry_requirement::merkle_validator::{
    IMerkleValidatorDispatcher, IMerkleValidatorDispatcherTrait,
};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

// ========================================
// Helpers
// ========================================

fn owner_address() -> ContractAddress {
    0x1234.try_into().unwrap()
}

fn address1() -> ContractAddress {
    0x1_felt252.try_into().unwrap()
}

fn address2() -> ContractAddress {
    0x2_felt252.try_into().unwrap()
}

fn address3() -> ContractAddress {
    0x3_felt252.try_into().unwrap()
}

fn address4() -> ContractAddress {
    0x4_felt252.try_into().unwrap()
}

/// Compute the leaf value (what gets passed to StandardMerkleTree)
fn compute_leaf_value(address: ContractAddress, count: u32) -> felt252 {
    PedersenTrait::new(0).update(address.into()).update(count.into()).finalize()
}

/// Compute the StandardMerkleTree leaf hash: H(0, value, 1)
fn compute_leaf_hash(address: ContractAddress, count: u32) -> felt252 {
    let value = compute_leaf_value(address, count);
    PedersenTrait::new(0).update(value).update(1).finalize()
}

/// OZ PedersenCHasher commutative hash: H(0, sorted_a, sorted_b, 2)
fn commutative_hash(a: felt252, b: felt252) -> felt252 {
    let a_u256: u256 = a.into();
    let b_u256: u256 = b.into();
    if a_u256 < b_u256 {
        PedersenTrait::new(0).update(a).update(b).update(2).finalize()
    } else {
        PedersenTrait::new(0).update(b).update(a).update(2).finalize()
    }
}

/// Sorts 4 leaves and returns them in ascending order by u256 value.
fn sort_leaves() -> (
    (felt252, ContractAddress, u32),
    (felt252, ContractAddress, u32),
    (felt252, ContractAddress, u32),
    (felt252, ContractAddress, u32),
) {
    // Use leaf_hash (not leaf_value) for sorting, as that's what the tree operates on
    let leaf1 = compute_leaf_hash(address1(), 3);
    let leaf2 = compute_leaf_hash(address2(), 5);
    let leaf3 = compute_leaf_hash(address3(), 1);
    let leaf4 = compute_leaf_hash(address4(), 2);

    let mut arr: Array<(felt252, ContractAddress, u32)> = array![
        (leaf1, address1(), 3), (leaf2, address2(), 5), (leaf3, address3(), 1),
        (leaf4, address4(), 2),
    ];

    let a = *arr.at(0);
    let b = *arr.at(1);
    let c = *arr.at(2);
    let d = *arr.at(3);

    let (a, b) = sort_two(a, b);
    let (c, d) = sort_two(c, d);
    let (a, c) = sort_two(a, c);
    let (b, d) = sort_two(b, d);
    let (b, c) = sort_two(b, c);

    (a, b, c, d)
}

fn sort_two(
    a: (felt252, ContractAddress, u32), b: (felt252, ContractAddress, u32),
) -> ((felt252, ContractAddress, u32), (felt252, ContractAddress, u32)) {
    let (a_leaf, _, _) = a;
    let (b_leaf, _, _) = b;
    let a_u256: u256 = a_leaf.into();
    let b_u256: u256 = b_leaf.into();
    if a_u256 <= b_u256 {
        (a, b)
    } else {
        (b, a)
    }
}

/// Returns (root, n01, n23, sorted leaves as 4-tuple)
fn build_tree_parts() -> (
    felt252,
    felt252,
    felt252,
    (felt252, ContractAddress, u32),
    (felt252, ContractAddress, u32),
    (felt252, ContractAddress, u32),
    (felt252, ContractAddress, u32),
) {
    let (s0, s1, s2, s3) = sort_leaves();
    let (s0_leaf, _, _) = s0;
    let (s1_leaf, _, _) = s1;
    let (s2_leaf, _, _) = s2;
    let (s3_leaf, _, _) = s3;

    let n01 = commutative_hash(s0_leaf, s1_leaf);
    let n23 = commutative_hash(s2_leaf, s3_leaf);
    let root = commutative_hash(n01, n23);

    (root, n01, n23, s0, s1, s2, s3)
}

fn get_proof_for_index(
    index: u32,
    s0_leaf: felt252,
    s1_leaf: felt252,
    s2_leaf: felt252,
    s3_leaf: felt252,
    n01: felt252,
    n23: felt252,
) -> Array<felt252> {
    if index == 0 {
        array![s1_leaf, n23]
    } else if index == 1 {
        array![s0_leaf, n23]
    } else if index == 2 {
        array![s3_leaf, n01]
    } else {
        array![s2_leaf, n01]
    }
}

fn deploy_merkle_validator() -> ContractAddress {
    let contract = declare("MerkleValidator").unwrap().contract_class();
    let (contract_address, _) = contract.deploy(@array![]).unwrap();
    contract_address
}

fn configure_merkle_validator(
    validator_address: ContractAddress, context_id: u64, entry_limit: u32, root: felt252,
) {
    let merkle = IMerkleValidatorDispatcher { contract_address: validator_address };
    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    start_cheat_caller_address(validator_address, owner_address());
    let tree_id = merkle.create_tree(root);
    stop_cheat_caller_address(validator_address);

    start_cheat_caller_address(validator_address, owner_address());
    validator.add_config(context_id, entry_limit, array![tree_id.into()].span());
    stop_cheat_caller_address(validator_address);
}

fn build_qualification(count: u32, proof: Span<felt252>) -> Array<felt252> {
    let mut qual: Array<felt252> = array![count.into()];
    let mut i: u32 = 0;
    while i < proof.len() {
        qual.append(*proof.at(i));
        i += 1;
    }
    qual
}

// ========================================
// Tests
// ========================================

#[test]
fn test_merkle_valid_proof() {
    let (root, n01, n23, s0, s1, s2, s3) = build_tree_parts();
    let context_id: u64 = 1;
    let validator_address = deploy_merkle_validator();
    configure_merkle_validator(validator_address, context_id, 0, root);

    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };
    let merkle = IMerkleValidatorDispatcher { contract_address: validator_address };

    let tree_id = merkle.get_context_tree(owner_address(), context_id);
    assert!(merkle.get_tree_root(tree_id) == root, "Root should match");

    let (s0_leaf, _, _) = s0;
    let (s1_leaf, _, _) = s1;
    let (s2_leaf, _, _) = s2;
    let (s3_leaf, _, _) = s3;

    let leaves: Array<(felt252, ContractAddress, u32)> = array![s0, s1, s2, s3];
    let mut i: u32 = 0;
    while i < 4 {
        let (_, addr, count) = *leaves.at(i);
        let proof = get_proof_for_index(i, s0_leaf, s1_leaf, s2_leaf, s3_leaf, n01, n23);
        let qual = build_qualification(count, proof.span());
        let valid = validator.valid_entry(owner_address(), context_id, addr, qual.span());
        assert!(valid, "Leaf should be valid");

        let proof2 = get_proof_for_index(i, s0_leaf, s1_leaf, s2_leaf, s3_leaf, n01, n23);
        let vp = merkle.verify_proof(tree_id, addr, count, proof2.span());
        assert!(vp, "verify_proof should return true");
        i += 1;
    };
}

#[test]
fn test_merkle_invalid_proof() {
    let (root, n01, n23, s0, s1, s2, s3) = build_tree_parts();
    let context_id: u64 = 1;
    let validator_address = deploy_merkle_validator();
    configure_merkle_validator(validator_address, context_id, 0, root);

    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    let (s0_leaf, s0_addr, s0_count) = s0;
    let (s1_leaf, _, _) = s1;
    let (s2_leaf, _, _) = s2;
    let (s3_leaf, _, _) = s3;

    let proof = get_proof_for_index(0, s0_leaf, s1_leaf, s2_leaf, s3_leaf, n01, n23);
    let tampered_elem = *proof.at(0) + 1;
    let bad_proof: Array<felt252> = array![tampered_elem, *proof.at(1)];

    let qual = build_qualification(s0_count, bad_proof.span());
    let valid = validator.valid_entry(owner_address(), context_id, s0_addr, qual.span());
    assert!(!valid, "Tampered proof should be invalid");
}

#[test]
fn test_merkle_wrong_address() {
    let (root, n01, n23, s0, s1, s2, s3) = build_tree_parts();
    let context_id: u64 = 1;
    let validator_address = deploy_merkle_validator();
    configure_merkle_validator(validator_address, context_id, 0, root);

    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    let (s0_leaf, _, s0_count) = s0;
    let (s1_leaf, _, _) = s1;
    let (s2_leaf, _, _) = s2;
    let (s3_leaf, _, _) = s3;

    let wrong_addr: ContractAddress = 0xDEAD_felt252.try_into().unwrap();
    let proof = get_proof_for_index(0, s0_leaf, s1_leaf, s2_leaf, s3_leaf, n01, n23);
    let qual = build_qualification(s0_count, proof.span());
    let valid = validator.valid_entry(owner_address(), context_id, wrong_addr, qual.span());
    assert!(!valid, "Wrong address should fail verification");
}

#[test]
fn test_merkle_wrong_count() {
    let (root, n01, n23, s0, s1, s2, s3) = build_tree_parts();
    let context_id: u64 = 1;
    let validator_address = deploy_merkle_validator();
    configure_merkle_validator(validator_address, context_id, 0, root);

    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    let (s0_leaf, s0_addr, s0_count) = s0;
    let (s1_leaf, _, _) = s1;
    let (s2_leaf, _, _) = s2;
    let (s3_leaf, _, _) = s3;

    let wrong_count: u32 = s0_count + 1;
    let proof = get_proof_for_index(0, s0_leaf, s1_leaf, s2_leaf, s3_leaf, n01, n23);
    let qual = build_qualification(wrong_count, proof.span());
    let valid = validator.valid_entry(owner_address(), context_id, s0_addr, qual.span());
    assert!(!valid, "Wrong count should fail verification");
}

#[test]
fn test_merkle_entries_left() {
    let (root, n01, n23, s0, s1, s2, s3) = build_tree_parts();
    let context_id: u64 = 1;
    let validator_address = deploy_merkle_validator();
    configure_merkle_validator(validator_address, context_id, 0, root);

    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    let (s0_leaf, _, _) = s0;
    let (s1_leaf, _, _) = s1;
    let (s2_leaf, _, _) = s2;
    let (s3_leaf, _, _) = s3;

    let leaves: Array<(felt252, ContractAddress, u32)> = array![s0, s1, s2, s3];
    let mut i: u32 = 0;
    while i < 4 {
        let (_, addr, count) = *leaves.at(i);
        let proof = get_proof_for_index(i, s0_leaf, s1_leaf, s2_leaf, s3_leaf, n01, n23);
        let qual = build_qualification(count, proof.span());
        let left = validator.entries_left(owner_address(), context_id, addr, qual.span());
        assert!(left.is_some(), "Should have limited entries");
        assert!(left.unwrap() == count, "entries_left should equal count from tree");
        i += 1;
    };
}

#[test]
fn test_merkle_entry_tracking() {
    let (root, n01, n23, s0, s1, s2, s3) = build_tree_parts();
    let context_id: u64 = 1;
    let validator_address = deploy_merkle_validator();
    configure_merkle_validator(validator_address, context_id, 0, root);

    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    let (s0_leaf, s0_addr, s0_count) = s0;
    let (s1_leaf, _, _) = s1;
    let (s2_leaf, _, _) = s2;
    let (s3_leaf, _, _) = s3;

    let proof = get_proof_for_index(0, s0_leaf, s1_leaf, s2_leaf, s3_leaf, n01, n23);
    let qual = build_qualification(s0_count, proof.span());
    let initial = validator.entries_left(owner_address(), context_id, s0_addr, qual.span());
    assert!(initial.unwrap() == s0_count, "Should start with full count");

    // Add an entry
    let qual_add = build_qualification(
        s0_count, get_proof_for_index(0, s0_leaf, s1_leaf, s2_leaf, s3_leaf, n01, n23).span(),
    );
    start_cheat_caller_address(validator_address, owner_address());
    validator.add_entry(context_id, 0, s0_addr, qual_add.span());
    stop_cheat_caller_address(validator_address);

    let qual_check = build_qualification(
        s0_count, get_proof_for_index(0, s0_leaf, s1_leaf, s2_leaf, s3_leaf, n01, n23).span(),
    );
    let after_add = validator.entries_left(owner_address(), context_id, s0_addr, qual_check.span());
    assert!(after_add.unwrap() == s0_count - 1, "Should decrement after add_entry");

    // Remove the entry
    let qual_rm = build_qualification(
        s0_count, get_proof_for_index(0, s0_leaf, s1_leaf, s2_leaf, s3_leaf, n01, n23).span(),
    );
    start_cheat_caller_address(validator_address, owner_address());
    validator.remove_entry(context_id, 0, s0_addr, qual_rm.span());
    stop_cheat_caller_address(validator_address);

    let qual_final = build_qualification(
        s0_count, get_proof_for_index(0, s0_leaf, s1_leaf, s2_leaf, s3_leaf, n01, n23).span(),
    );
    let after_remove = validator
        .entries_left(owner_address(), context_id, s0_addr, qual_final.span());
    assert!(after_remove.unwrap() == s0_count, "Should increment after remove_entry");
}

#[test]
fn test_merkle_entry_limit_cap() {
    let (root, n01, n23, s0, s1, s2, s3) = build_tree_parts();
    let context_id: u64 = 1;
    let validator_address = deploy_merkle_validator();
    let entry_limit: u32 = 2;
    configure_merkle_validator(validator_address, context_id, entry_limit, root);

    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    let (s0_leaf, _, _) = s0;
    let (s1_leaf, _, _) = s1;
    let (s2_leaf, _, _) = s2;
    let (s3_leaf, _, _) = s3;

    let leaves: Array<(felt252, ContractAddress, u32)> = array![s0, s1, s2, s3];
    let mut i: u32 = 0;
    let mut found = false;
    while i < 4 {
        let (_, addr, count) = *leaves.at(i);
        if addr == address2() {
            let proof = get_proof_for_index(i, s0_leaf, s1_leaf, s2_leaf, s3_leaf, n01, n23);
            let qual = build_qualification(count, proof.span());
            let left = validator.entries_left(owner_address(), context_id, addr, qual.span());
            assert!(left.is_some(), "Should have limited entries");
            assert!(left.unwrap() == entry_limit, "entries_left should be capped by entry_limit");
            found = true;
            break;
        }
        i += 1;
    }
    assert!(found, "address2 should be found in sorted leaves");
}

#[test]
fn test_merkle_single_leaf() {
    let addr = address1();
    let count: u32 = 3;
    // For a single leaf, root = leaf_hash (no branch hashing needed)
    let root = compute_leaf_hash(addr, count);

    let context_id: u64 = 42;
    let validator_address = deploy_merkle_validator();
    configure_merkle_validator(validator_address, context_id, 0, root);

    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };
    let merkle = IMerkleValidatorDispatcher { contract_address: validator_address };

    let qual = build_qualification(count, array![].span());
    let valid = validator.valid_entry(owner_address(), context_id, addr, qual.span());
    assert!(valid, "Single leaf should be valid with empty proof");

    let tree_id = merkle.get_context_tree(owner_address(), context_id);
    let vp = merkle.verify_proof(tree_id, addr, count, array![].span());
    assert!(vp, "verify_proof should work for single leaf");

    let wrong_qual = build_qualification(count, array![].span());
    let wrong_valid = validator
        .valid_entry(owner_address(), context_id, address2(), wrong_qual.span());
    assert!(!wrong_valid, "Wrong address should fail for single leaf tree");
}

#[test]
fn test_merkle_should_ban_returns_false() {
    let (root, n01, n23, s0, s1, s2, s3) = build_tree_parts();
    let context_id: u64 = 1;
    let validator_address = deploy_merkle_validator();
    configure_merkle_validator(validator_address, context_id, 0, root);

    let validator = IEntryRequirementExtensionDispatcher { contract_address: validator_address };

    let (s0_leaf, s0_addr, s0_count) = s0;
    let (s1_leaf, _, _) = s1;
    let (s2_leaf, _, _) = s2;
    let (s3_leaf, _, _) = s3;

    let proof = get_proof_for_index(0, s0_leaf, s1_leaf, s2_leaf, s3_leaf, n01, n23);
    let qual = build_qualification(s0_count, proof.span());

    let should_ban = validator.should_ban(owner_address(), context_id, 1, s0_addr, qual.span());
    assert!(!should_ban, "MerkleValidator should never ban");

    let random_addr: ContractAddress = 0xBEEF_felt252.try_into().unwrap();
    let should_ban_random = validator
        .should_ban(owner_address(), context_id, 99, random_addr, array![].span());
    assert!(!should_ban_random, "should_ban should always return false");
}
