// SPDX-License-Identifier: MIT

//! KYC Badge Entry Validator
//!
//! Gates tournament entry on a dedicated soulbound "KYC verified" badge. Reads the
//! `KycBadge` contract's `has_badge(account)` and admits only accounts that hold a
//! (non-revoked) badge.
//!
//! This is the on-chain consumer of the off-chain zkpassport → badge flow (the
//! `verification-app` mints the badge after verifying a zkpassport proof
//! server-side). Compared with `kyc_registry_validator` (which reads attributes
//! from the zk-kyc-demo registry), this reads only a **boolean credential** — no
//! attributes on-chain, preserving zkpassport's privacy. The badge is its own
//! contract (separate from any task/membership badges) and is **revocable**, so a
//! withdrawn KYC status is reflected here (and is bannable, if configured).
//!
//! Configuration (via add_config):
//!   config[0]: badge_address - The KycBadge contract
//!   config[1]: bannable      - Optional (default 0). If 1, losing the badge makes
//!                              the entry bannable via `should_ban`.
//!
//! Qualification: none — membership is per-account. `qualification` MUST be empty.

use starknet::ContractAddress;

/// Minimal mirror of the KycBadge read surface (declared locally to avoid a
/// dependency on the whole contract — a dispatcher only needs the ABI).
#[starknet::interface]
pub trait IKycBadge<TContractState> {
    fn has_badge(self: @TContractState, account: ContractAddress) -> bool;
}

#[starknet::interface]
pub trait IKycBadgeValidator<TState> {
    fn get_badge_address(
        self: @TState, context_owner: ContractAddress, context_id: u64,
    ) -> ContractAddress;
}

#[starknet::contract]
pub mod KycBadgeValidator {
    use core::num::traits::Zero;
    use metagame_extensions_entry_requirement::entry_requirement_extension_component::EntryRequirementExtensionComponent;
    use metagame_extensions_entry_requirement::entry_requirement_extension_component::EntryRequirementExtensionComponent::EntryRequirementExtension;
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use super::{IKycBadgeDispatcher, IKycBadgeDispatcherTrait, IKycBadgeValidator};

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
        // Per-context config
        context_badge_address: Map<(ContractAddress, u64), ContractAddress>,
        // Entry tracking
        context_entry_limit: Map<(ContractAddress, u64), u32>,
        context_entries_per_address: Map<(ContractAddress, u64, ContractAddress), u32>,
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

    impl EntryRequirementExtensionImplInternal of EntryRequirementExtension<ContractState> {
        fn validate_entry(
            self: @ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            // Per-account gate: no proof is carried in the qualification.
            if qualification.len() != 0 {
                return false;
            }

            let badge_addr = self.context_badge_address.read((context_owner, context_id));
            if badge_addr.is_zero() {
                return false;
            }

            // Quota first: short-circuit before the cross-contract dispatch.
            let entry_limit = self.context_entry_limit.read((context_owner, context_id));
            if entry_limit != 0 {
                let used = self
                    .context_entries_per_address
                    .read((context_owner, context_id, player_address));
                if used >= entry_limit {
                    return false;
                }
            }

            IKycBadgeDispatcher { contract_address: badge_addr }.has_badge(player_address)
        }

        fn should_ban_entry(
            self: @ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            game_token_id: felt252,
            current_owner: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            // Only reached when configured bannable (the component guards). Ban if
            // the holder's KYC badge was revoked / is no longer held.
            let badge_addr = self.context_badge_address.read((context_owner, context_id));
            if badge_addr.is_zero() {
                return false;
            }
            !IKycBadgeDispatcher { contract_address: badge_addr }.has_badge(current_owner)
        }

        fn entries_left(
            self: @ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> Option<u32> {
            let badge_addr = self.context_badge_address.read((context_owner, context_id));
            if badge_addr.is_zero() {
                return Option::Some(0);
            }
            let member = IKycBadgeDispatcher { contract_address: badge_addr }
                .has_badge(player_address);
            if !member {
                return Option::Some(0);
            }

            let entry_limit = self.context_entry_limit.read((context_owner, context_id));
            if entry_limit == 0 {
                return Option::None; // unlimited
            }
            let used = self
                .context_entries_per_address
                .read((context_owner, context_id, player_address));
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
            assert!(config.len() >= 1, "KycBadgeValidator: config must have at least 1 element");
            let badge_addr: ContractAddress = (*config.at(0)).try_into().unwrap();
            assert!(!badge_addr.is_zero(), "KycBadgeValidator: badge address cannot be zero");

            let bannable: bool = if config.len() > 1 {
                (*config.at(1)) != 0
            } else {
                false
            };

            self.context_badge_address.write((context_owner, context_id), badge_addr);
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
            let used = self.context_entries_per_address.read(key);
            self.context_entries_per_address.write(key, used + 1);
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
            let used = self.context_entries_per_address.read(key);
            if used > 0 {
                self.context_entries_per_address.write(key, used - 1);
            }
        }
    }

    #[abi(embed_v0)]
    impl KycBadgeValidatorImpl of IKycBadgeValidator<ContractState> {
        fn get_badge_address(
            self: @ContractState, context_owner: ContractAddress, context_id: u64,
        ) -> ContractAddress {
            self.context_badge_address.read((context_owner, context_id))
        }
    }
}
