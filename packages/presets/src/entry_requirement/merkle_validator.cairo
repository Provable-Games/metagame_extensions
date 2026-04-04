use starknet::ContractAddress;

#[starknet::interface]
pub trait IMerkleValidator<TState> {
    fn create_tree(ref self: TState, root: felt252) -> u64;
    fn get_tree_root(self: @TState, tree_id: u64) -> felt252;
    fn get_tree_owner(self: @TState, tree_id: u64) -> ContractAddress;
    fn get_context_tree(self: @TState, context_id: u64) -> u64;
    fn verify_proof(
        self: @TState,
        tree_id: u64,
        player_address: ContractAddress,
        count: u8,
        proof: Span<felt252>,
    ) -> bool;
}

#[starknet::contract]
pub mod MerkleValidator {
    use core::hash::HashStateTrait;
    use core::pedersen::PedersenTrait;
    use metagame_extensions_entry_requirement::entry_requirement_extension_component::EntryRequirementExtensionComponent;
    use metagame_extensions_entry_requirement::entry_requirement_extension_component::EntryRequirementExtensionComponent::EntryRequirementExtension;
    use openzeppelin_introspection::src5::SRC5Component;
    use openzeppelin_merkle_tree::merkle_proof;
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_caller_address};

    component!(
        path: EntryRequirementExtensionComponent,
        storage: entry_validator,
        event: EntryValidatorEvent,
    );
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    #[abi(embed_v0)]
    impl EntryRequirementExtensionImpl =
        EntryRequirementExtensionComponent::EntryRequirementExtensionImpl<ContractState>;
    impl EntryRequirementExtensionInternalImpl =
        EntryRequirementExtensionComponent::InternalImpl<ContractState>;

    #[abi(embed_v0)]
    impl SRC5Impl = SRC5Component::SRC5Impl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        entry_validator: EntryRequirementExtensionComponent::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        // Tree registry
        tree_id_counter: u64,
        tree_roots: Map<u64, felt252>,
        tree_owner: Map<u64, ContractAddress>,
        // Context -> tree mapping
        context_tree: Map<u64, u64>,
        // Entry tracking
        merkle_entry_limit: Map<u64, u8>,
        merkle_entry_count: Map<(u64, ContractAddress), u8>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        EntryValidatorEvent: EntryRequirementExtensionComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        TreeCreated: TreeCreated,
    }

    #[derive(Drop, starknet::Event)]
    struct TreeCreated {
        #[key]
        tree_id: u64,
        #[key]
        owner: ContractAddress,
        root: felt252,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.entry_validator.initializer(false);
    }

    /// Compute the leaf hash matching OZ StandardMerkleTree / @ericnordelo/strk-merkle-tree.
    /// The leaf is a single felt252 value (the pre-hashed leaf), which gets double-hashed
    /// by the StandardMerkleTree. We compute the pre-hash here as pedersen(address, count),
    /// and the tree library handles the leaf hashing (pedersen(0, value, 1)).
    ///
    /// For our use case, the leaf value passed to the tree is:
    ///   pedersen(pedersen(0, address), count)  (i.e.
    ///   PedersenTrait::new(0).update(addr).update(count).finalize())
    ///
    /// The StandardMerkleTree then applies its leaf hash:
    ///   leaf_hash = PedersenTrait::new(0).update(value).update(1).finalize()
    ///
    /// And the branch hash is:
    ///   PedersenTrait::new(0).update(a).update(b).update(2).finalize() (sorted)
    ///
    /// We store the root as produced by the StandardMerkleTree, and verify with OZ's
    /// verify_pedersen which uses the same commutative hash (with length suffix).
    ///
    /// The leaf_hash passed to verify_pedersen must be the StandardMerkleTree leaf hash:
    fn compute_leaf_hash(address: ContractAddress, count: u8) -> felt252 {
        // First compute the leaf value (what gets passed to StandardMerkleTree.of([[value]]))
        let leaf_value = PedersenTrait::new(0)
            .update(address.into())
            .update(count.into())
            .finalize();
        // Then apply the StandardMerkleTree leaf hashing: H(0, value, 1)
        PedersenTrait::new(0).update(leaf_value).update(1).finalize()
    }

    impl EntryRequirementExtensionImplInternal of EntryRequirementExtension<ContractState> {
        fn validate_entry(
            self: @ContractState,
            context_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            assert!(qualification.len() >= 1, "MerkleValidator: qualification too short");

            let count_felt: felt252 = *qualification.at(0);
            let count: u8 = count_felt.try_into().unwrap();
            let proof = qualification.slice(1, qualification.len() - 1);

            let tree_id = self.context_tree.read(context_id);
            let root = self.tree_roots.read(tree_id);

            if root == 0 {
                return false;
            }

            let leaf_hash = compute_leaf_hash(player_address, count);
            merkle_proof::verify_pedersen(proof, root, leaf_hash)
        }

        fn should_ban_entry(
            self: @ContractState,
            context_id: u64,
            game_token_id: felt252,
            current_owner: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            false
        }

        fn entries_left(
            self: @ContractState,
            context_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> Option<u8> {
            if qualification.len() < 1 {
                return Option::Some(0);
            }

            let count_felt: felt252 = *qualification.at(0);
            let count: u8 = count_felt.try_into().unwrap();
            let proof = qualification.slice(1, qualification.len() - 1);

            let tree_id = self.context_tree.read(context_id);
            let root = self.tree_roots.read(tree_id);

            if root == 0 {
                return Option::Some(0);
            }

            let leaf_hash = compute_leaf_hash(player_address, count);
            if !merkle_proof::verify_pedersen(proof, root, leaf_hash) {
                return Option::Some(0);
            }

            let entry_limit = self.merkle_entry_limit.read(context_id);
            let effective_count = if entry_limit > 0 && count > entry_limit {
                entry_limit
            } else {
                count
            };

            let used = self.merkle_entry_count.read((context_id, player_address));
            if effective_count > used {
                Option::Some(effective_count - used)
            } else {
                Option::Some(0)
            }
        }

        fn add_config(
            ref self: ContractState, context_id: u64, entry_limit: u8, config: Span<felt252>,
        ) {
            assert!(config.len() >= 1, "MerkleValidator: config must contain tree ID");
            let tree_id_felt: felt252 = *config.at(0);
            let tree_id: u64 = tree_id_felt.try_into().unwrap();
            let root = self.tree_roots.read(tree_id);
            assert!(root != 0, "MerkleValidator: tree does not exist");
            self.context_tree.write(context_id, tree_id);
            self.merkle_entry_limit.write(context_id, entry_limit);
        }

        fn on_entry_added(
            ref self: ContractState,
            context_id: u64,
            game_token_id: felt252,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) {
            let used = self.merkle_entry_count.read((context_id, player_address));
            self.merkle_entry_count.write((context_id, player_address), used + 1);
        }

        fn on_entry_removed(
            ref self: ContractState,
            context_id: u64,
            game_token_id: felt252,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) {
            let used = self.merkle_entry_count.read((context_id, player_address));
            if used > 0 {
                self.merkle_entry_count.write((context_id, player_address), used - 1);
            }
        }
    }
    use super::IMerkleValidator;
    #[abi(embed_v0)]
    impl MerkleValidatorImpl of IMerkleValidator<ContractState> {
        fn create_tree(ref self: ContractState, root: felt252) -> u64 {
            assert!(root != 0, "MerkleValidator: root cannot be zero");
            let current_id = self.tree_id_counter.read();
            let new_id = current_id + 1;
            let caller = get_caller_address();

            self.tree_roots.write(new_id, root);
            self.tree_owner.write(new_id, caller);
            self.tree_id_counter.write(new_id);

            self.emit(TreeCreated { tree_id: new_id, owner: caller, root });

            new_id
        }

        fn get_tree_root(self: @ContractState, tree_id: u64) -> felt252 {
            self.tree_roots.read(tree_id)
        }

        fn get_tree_owner(self: @ContractState, tree_id: u64) -> ContractAddress {
            self.tree_owner.read(tree_id)
        }

        fn get_context_tree(self: @ContractState, context_id: u64) -> u64 {
            self.context_tree.read(context_id)
        }

        fn verify_proof(
            self: @ContractState,
            tree_id: u64,
            player_address: ContractAddress,
            count: u8,
            proof: Span<felt252>,
        ) -> bool {
            let root = self.tree_roots.read(tree_id);
            if root == 0 {
                return false;
            }
            let leaf_hash = compute_leaf_hash(player_address, count);
            merkle_proof::verify_pedersen(proof, root, leaf_hash)
        }
    }
}
