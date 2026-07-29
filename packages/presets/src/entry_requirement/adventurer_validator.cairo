//! Adventurer Validator - Objective Based
//!
//! Thin entry-requirement adapter that gates tournament entry on a Death Mountain
//! adventurer having completed a registered objective on the **Adventurer Oracle**
//! (see `metagame-extensions/packages/adventurer_oracle`). The oracle is the source of
//! truth for "did adventurer `token_id` complete objective `objective_id`"; this
//! validator simply forwards that question through the metagame `entry_requirement`
//! framework so Budokan can use "completed objective N" as an entry gate.
//!
//! The validator stays game-agnostic: it only speaks the `IMinigameObjectives`
//! interface (SNIP-5 `completed_objective`), so any objectives provider conforming to
//! that interface works, not just the adventurer oracle.
//!
//! ## How It Works
//! - Each `(context_owner, context_id)` is configured with an oracle address and a
//!   single `objective_id`.
//! - The player supplies the adventurer NFT `token_id` they are qualifying with as the
//!   first (and only) element of the `qualification` span.
//! - Entry is granted iff `oracle.completed_objective(token_id, objective_id) == true`
//!   and the player is under their per-context entry quota (`entry_limit`).
//!
//! ## Configuration (via add_config)
//! `entry_limit` (framework param): max entries per player for this context (0 = unlimited).
//! `config` span:
//! - config[0]: oracle address (ContractAddress) - the objectives provider to query.
//! - config[1]: objective_id (u32) - the objective the adventurer must have completed.
//! - config[2]: bannable (bool, optional) - if set, an existing entry is banned when the
//!   objective is no longer satisfied (objectives read live state, so e.g. a gold check
//!   can regress). Defaults to false (non-bannable) when omitted.
//!
//! ## Qualification (per entry)
//! `qualification` span:
//! - qualification[0]: adventurer NFT token_id (felt252).

use starknet::ContractAddress;

/// Minimal mirror of the objectives-provider interface (`IMinigameObjectives`) this
/// validator delegates to. Declared locally so the preset does not take a code
/// dependency on the oracle crate — matching the "define the minimal interface locally"
/// convention used by the other presets (e.g. `IAbbot` in `opus_troves_validator`).
#[starknet::interface]
pub trait IMinigameObjectives<TState> {
    fn completed_objective(self: @TState, token_id: felt252, objective_id: u32) -> bool;
}

#[starknet::interface]
pub trait IAdventurerValidator<TState> {
    fn get_oracle(
        self: @TState, context_owner: ContractAddress, context_id: u64,
    ) -> ContractAddress;
    fn get_objective_id(self: @TState, context_owner: ContractAddress, context_id: u64) -> u32;
    fn get_entry_limit(self: @TState, context_owner: ContractAddress, context_id: u64) -> u32;
}

#[starknet::contract]
pub mod AdventurerValidator {
    use core::num::traits::Zero;
    use metagame_extensions_entry_requirement::entry_requirement_extension_component::EntryRequirementExtensionComponent;
    use metagame_extensions_entry_requirement::entry_requirement_extension_component::EntryRequirementExtensionComponent::EntryRequirementExtension;
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use super::{IMinigameObjectivesDispatcher, IMinigameObjectivesDispatcherTrait};

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
        // Objectives provider (oracle) to query per context.
        context_oracle: Map<(ContractAddress, u64), ContractAddress>,
        // Objective the adventurer must have completed per context.
        context_objective_id: Map<(ContractAddress, u64), u32>,
        // Per-player entry cap per context (0 = unlimited).
        context_entry_limit: Map<(ContractAddress, u64), u32>,
        // Entries consumed per player per context.
        context_entries_used: Map<(ContractAddress, u64, ContractAddress), u32>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        EntryValidatorEvent: EntryRequirementExtensionComponent::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.entry_validator.initializer();
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Read the adventurer token_id the player is qualifying with. Returns `None`
        /// when the qualification data is malformed (empty), which callers treat as
        /// "does not qualify".
        fn qualifying_token_id(
            self: @ContractState, qualification: Span<felt252>,
        ) -> Option<felt252> {
            if qualification.len() == 0 {
                return Option::None;
            }
            Option::Some(*qualification.at(0))
        }

        /// True iff the configured oracle reports the qualifying adventurer has completed
        /// this context's objective. False when unconfigured or malformed.
        fn objective_satisfied(
            self: @ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            qualification: Span<felt252>,
        ) -> bool {
            let oracle = self.context_oracle.read((context_owner, context_id));
            if oracle.is_zero() {
                return false;
            }
            let token_id = match self.qualifying_token_id(qualification) {
                Option::Some(id) => id,
                Option::None => { return false; },
            };
            let objective_id = self.context_objective_id.read((context_owner, context_id));
            IMinigameObjectivesDispatcher { contract_address: oracle }
                .completed_objective(token_id, objective_id)
        }
    }

    impl EntryRequirementExtensionImplInternal of EntryRequirementExtension<ContractState> {
        fn validate_entry(
            self: @ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            if !self.objective_satisfied(context_owner, context_id, qualification) {
                return false;
            }

            let entry_limit = self.context_entry_limit.read((context_owner, context_id));
            if entry_limit == 0 {
                return true;
            }
            let used = self.context_entries_used.read((context_owner, context_id, player_address));
            used < entry_limit
        }

        fn should_ban_entry(
            self: @ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            game_token_id: felt252,
            current_owner: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            // Only reached when the context was configured bannable. Ban once the
            // objective is no longer satisfied for the qualifying adventurer.
            !self.objective_satisfied(context_owner, context_id, qualification)
        }

        fn entries_left(
            self: @ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> Option<u32> {
            if !self.objective_satisfied(context_owner, context_id, qualification) {
                return Option::Some(0);
            }
            let entry_limit = self.context_entry_limit.read((context_owner, context_id));
            if entry_limit == 0 {
                // Unlimited entries while the objective stays satisfied.
                return Option::None;
            }
            let used = self.context_entries_used.read((context_owner, context_id, player_address));
            if entry_limit > used {
                Option::Some(entry_limit - used)
            } else {
                Option::Some(0)
            }
        }

        fn add_config(
            ref self: ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            entry_limit: u32,
            config: Span<felt252>,
        ) {
            assert!(config.len() >= 2, "AdventurerValidator: config too short");
            let oracle: ContractAddress = (*config.at(0)).try_into().unwrap();
            assert!(!oracle.is_zero(), "AdventurerValidator: oracle is zero");
            let objective_id: u32 = (*config.at(1)).try_into().unwrap();

            let bannable: bool = if config.len() > 2 {
                *config.at(2) != 0
            } else {
                false
            };

            self.context_oracle.write((context_owner, context_id), oracle);
            self.context_objective_id.write((context_owner, context_id), objective_id);
            self.context_entry_limit.write((context_owner, context_id), entry_limit);
            self.entry_validator.set_bannable(context_owner, context_id, bannable);
        }

        fn on_entry_added(
            ref self: ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            game_token_id: felt252,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) {
            let key = (context_owner, context_id, player_address);
            let used = self.context_entries_used.read(key);
            self.context_entries_used.write(key, used + 1);
        }

        fn on_entry_removed(
            ref self: ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            game_token_id: felt252,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) {
            let key = (context_owner, context_id, player_address);
            let used = self.context_entries_used.read(key);
            if used > 0 {
                self.context_entries_used.write(key, used - 1);
            }
        }
    }
    use super::IAdventurerValidator;
    #[abi(embed_v0)]
    impl AdventurerValidatorImpl of IAdventurerValidator<ContractState> {
        fn get_oracle(
            self: @ContractState, context_owner: ContractAddress, context_id: u64,
        ) -> ContractAddress {
            self.context_oracle.read((context_owner, context_id))
        }

        fn get_objective_id(
            self: @ContractState, context_owner: ContractAddress, context_id: u64,
        ) -> u32 {
            self.context_objective_id.read((context_owner, context_id))
        }

        fn get_entry_limit(
            self: @ContractState, context_owner: ContractAddress, context_id: u64,
        ) -> u32 {
            self.context_entry_limit.read((context_owner, context_id))
        }
    }
}
