// SPDX-License-Identifier: MIT

//! KYC Registry Entry Validator
//!
//! Gates tournament entry on a passport-proven zk-KYC registration held by the
//! **entering account**. Reads the `zk-kyc-demo` KYC registry (an on-chain attribute
//! store) via cross-contract dispatch and admits only accounts that are
//! **registered + over-18**.
//!
//! Trust root: the `zk-kyc-demo` registry (`get_props`). The over-18 claim is proven
//! once, off the hot path, when the holder scans their passport and registers; this
//! validator simply reads the persisted result. See this package's
//! `zkpassport_validator` for the alternative proof-on-demand trust root (no registry).
//!
//! ⚠️ Privacy note: the registry it reads stores `{registered, over_18, is_citizen,
//! sex}` publicly per account and a passport-nullifier → account map. That carries
//! deanonymization / honeypot risk (an MRZ holder can recompute the nullifier and look
//! up the account). This validator only consumes `registered + over_18`, but the
//! exposure lives in the registry regardless. See the package README.
//!
//! Configuration (via add_config):
//!   config[0]: registry_address - Deployed KYC registry (zk-kyc-demo)
//!   config[1]: bannable         - Optional (default 0). If 1, a revoked registration
//!                                 (registry `delete_registration`) makes the entry
//!                                 bannable via `should_ban`.
//!
//! Qualification: none — this is a per-account gate. `qualification` MUST be empty.
//! (One-human-one-entry would instead carry the passport `id` and check
//! `registry.id_owner(id) == player`; out of scope for the per-account policy.)

use starknet::ContractAddress;

/// Per-account KYC attributes proven from a genuine passport. Field order is
/// load-bearing — it mirrors `KycRegistry::Props` in `zk-kyc-demo` exactly, so the
/// cross-contract return decodes correctly.
#[derive(Serde, Drop, Copy)]
pub struct Props {
    pub registered: bool,
    pub over_18: bool,
    pub is_citizen: bool,
    pub sex: felt252,
}

/// Minimal mirror of the zk-KYC registry read surface (declared locally to avoid a
/// dependency on the whole zk-kyc-demo crate — a dispatcher only needs the ABI).
#[starknet::interface]
pub trait IKycRegistry<TContractState> {
    fn get_props(self: @TContractState, account: ContractAddress) -> Props;
    fn is_registered(self: @TContractState, account: ContractAddress) -> bool;
}

#[starknet::interface]
pub trait IKycRegistryValidator<TState> {
    fn get_registry_address(
        self: @TState, context_owner: ContractAddress, context_id: u64,
    ) -> ContractAddress;
    fn get_entry_limit(self: @TState, context_owner: ContractAddress, context_id: u64) -> u32;
}

#[starknet::contract]
pub mod KycRegistryValidator {
    use core::num::traits::Zero;
    use metagame_extensions_entry_requirement::entry_requirement_extension_component::EntryRequirementExtensionComponent;
    use metagame_extensions_entry_requirement::entry_requirement_extension_component::EntryRequirementExtensionComponent::EntryRequirementExtension;
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use super::{IKycRegistryDispatcher, IKycRegistryDispatcherTrait, IKycRegistryValidator};

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
        context_registry_address: Map<(ContractAddress, u64), ContractAddress>,
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

            let registry_addr = self.context_registry_address.read((context_owner, context_id));
            if registry_addr.is_zero() {
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

            // KYC gate: registered + over-18. `is_citizen` is intentionally ignored.
            let props = IKycRegistryDispatcher { contract_address: registry_addr }
                .get_props(player_address);
            props.registered && props.over_18
        }

        fn should_ban_entry(
            self: @ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            game_token_id: felt252,
            current_owner: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            // Only reached when the context was configured bannable (the component
            // guards on `bannable`). Ban if the holder's KYC no longer holds — e.g.
            // the registration was deleted from the registry.
            let registry_addr = self.context_registry_address.read((context_owner, context_id));
            if registry_addr.is_zero() {
                return false;
            }
            let props = IKycRegistryDispatcher { contract_address: registry_addr }
                .get_props(current_owner);
            !(props.registered && props.over_18)
        }

        fn entries_left(
            self: @ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> Option<u32> {
            // Not eligible -> no entries, matching validate_entry's rejection semantics.
            let registry_addr = self.context_registry_address.read((context_owner, context_id));
            if registry_addr.is_zero() {
                return Option::Some(0);
            }
            let props = IKycRegistryDispatcher { contract_address: registry_addr }
                .get_props(player_address);
            if !(props.registered && props.over_18) {
                return Option::Some(0);
            }

            let entry_limit = self.context_entry_limit.read((context_owner, context_id));
            if entry_limit == 0 {
                return Option::None; // unlimited
            }
            let used = self
                .context_entries_per_address
                .read((context_owner, context_id, player_address));
            // Saturating: guards against a later re-config lowering the limit below used.
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
            assert!(config.len() >= 1, "KycRegistryValidator: config must have at least 1 element");
            let registry_addr: ContractAddress = (*config.at(0)).try_into().unwrap();
            assert!(
                !registry_addr.is_zero(), "KycRegistryValidator: registry address cannot be zero",
            );

            let bannable: bool = if config.len() > 1 {
                (*config.at(1)) != 0
            } else {
                false
            };

            self.context_registry_address.write((context_owner, context_id), registry_addr);
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
    impl KycRegistryValidatorImpl of IKycRegistryValidator<ContractState> {
        fn get_registry_address(
            self: @ContractState, context_owner: ContractAddress, context_id: u64,
        ) -> ContractAddress {
            self.context_registry_address.read((context_owner, context_id))
        }

        fn get_entry_limit(
            self: @ContractState, context_owner: ContractAddress, context_id: u64,
        ) -> u32 {
            self.context_entry_limit.read((context_owner, context_id))
        }
    }
}
