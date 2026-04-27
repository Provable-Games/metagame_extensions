//! Opus Troves Validator - Debt Based
//!
//! This validator calculates tournament entries based on borrowed yin (stablecoin) from Opus
//! Protocol.
//! Players with active debt positions can enter tournaments, with entries scaling based on amount
//! borrowed.
//!
//! ## How It Works:
//! - Sums debt across ALL troves owned by a player
//! - Calculates entries: (total_debt - threshold) / value_per_entry
//! - Forging more yin → more entries
//! - Melting yin → fewer entries (can trigger banning if over quota)
//!
//! ## Configuration (via add_config):
//! - config[0]: asset_count (u8) - 0 = wildcard (all troves), N = filter by N assets
//! - config[1..N]: asset addresses (troves must contain at least one)
//! - config[N+1]: threshold (u128) - minimum yin debt to qualify (WAD UNITS: 1e18 = 1 yin)
//! - config[N+2]: value_per_entry (u128) - yin required per entry (WAD UNITS: 1e18 = 1 yin)
//! - config[N+3]: max_entries (u8) - maximum entries cap (0 = no cap)
//!
//! **IMPORTANT**: threshold and value_per_entry use WAD UNITS (18 decimals).
//! 1 yin = 1000000000000000000 (1e18). This gives maximum precision and control.
//!
//! ## Examples:
//!
//! ### Example 1: Wildcard - All borrowers (1 yin per entry)
//! ```
//! config = [0, 1000000000000000000, 1000000000000000000, 0]
//! // 0 assets (wildcard), 1 yin threshold, 1 yin per entry, no max
//! → Counts debt from ALL troves regardless of collateral
//! → Player with 3.5 yin debt gets (3.5e18 - 1e18) / 1e18 = 2 entries
//! ```
//!
//! ### Example 2: STRK borrowers only (0.5 yin per entry)
//! ```
//! config = [1, STRK_ADDRESS, 10000000000000000000, 500000000000000000, 10]
//! // 1 asset filter, 10 yin threshold, 0.5 yin per entry, max 10
//! → Only counts debt from troves backed by STRK
//! → Player with 30 yin debt gets (30e18 - 10e18) / 0.5e18 = 40 entries (capped at 10)
//! ```
//!
//! ### Example 3: Blue chip borrowers (2 yin per entry)
//! ```
//! config = [2, STRK_ADDRESS, WSTETH_ADDRESS, 5000000000000000000, 2000000000000000000, 0]
//! // 2 assets, 5 yin threshold, 2 yin per entry, no max
//! → Counts debt from troves backed by STRK OR wstETH
//! → Player with 25 yin debt gets (25e18 - 5e18) / 2e18 = 10 entries
//! ```

use metagame_extensions_presets::entry_requirement::externals::wadray::Wad;
use starknet::ContractAddress;

#[starknet::interface]
pub trait IAbbot<TContractState> {
    fn get_trove_owner(self: @TContractState, trove_id: u64) -> Option<ContractAddress>;
    fn get_user_trove_ids(self: @TContractState, user: ContractAddress) -> Span<u64>;
    fn get_troves_count(self: @TContractState) -> u64;
    fn get_trove_asset_balance(self: @TContractState, trove_id: u64, yang: ContractAddress) -> u128;
}

#[starknet::interface]
pub trait IShrine<TContractState> {
    fn get_trove_health(self: @TContractState, trove_id: u64) -> Health;
}

#[derive(Drop, Serde, Copy)]
pub struct Health {
    pub threshold: metagame_extensions_presets::entry_requirement::externals::wadray::Ray,
    pub ltv: metagame_extensions_presets::entry_requirement::externals::wadray::Ray,
    pub value: Wad,
    pub debt: Wad,
}

#[starknet::interface]
pub trait IOpusTrovesValidator<TState> {
    fn get_debt_threshold(self: @TState, context_owner: ContractAddress, context_id: u64) -> u128;
    fn get_value_per_entry(self: @TState, context_owner: ContractAddress, context_id: u64) -> u128;
    fn get_max_entries(self: @TState, context_owner: ContractAddress, context_id: u64) -> u32;
}

#[starknet::contract]
pub mod OpusTrovesValidator {
    use metagame_extensions_entry_requirement::entry_requirement_extension_component::EntryRequirementExtensionComponent;
    use metagame_extensions_entry_requirement::entry_requirement_extension_component::EntryRequirementExtensionComponent::EntryRequirementExtension;
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use super::{
        Health, IAbbotDispatcher, IAbbotDispatcherTrait, IShrineDispatcher, IShrineDispatcherTrait,
    };

    // Opus mainnet addresses
    fn abbot_address() -> ContractAddress {
        0x04d0bb0a4c40012384e7c419e6eb3c637b28e8363fb66958b60d90505b9c072f.try_into().unwrap()
    }

    fn shrine_address() -> ContractAddress {
        0x0498edfaf50ca5855666a700c25dd629d577eb9afccdf3b5977aec79aee55ada.try_into().unwrap()
    }

    fn fdp_address() -> ContractAddress {
        0x023037703b187f6ff23b883624a0a9f266c9d44671e762048c70100c2f128ab9.try_into().unwrap()
    }

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
        // Asset filtering (0 = wildcard, N = filter by N assets)
        context_asset_count: Map<(ContractAddress, u64), u8>,
        // Asset addresses for filtering (context_owner, context_id, index) -> address
        context_assets: Map<(ContractAddress, u64, u8), ContractAddress>,
        // Minimum debt threshold to qualify
        context_debt_threshold: Map<(ContractAddress, u64), u128>,
        // Fixed entry limit (0 = use value_per_entry instead)
        context_entry_limit: Map<(ContractAddress, u64), u32>,
        // Entry count per player
        context_entries_per_address: Map<(ContractAddress, u64, ContractAddress), u32>,
        // Debt required per entry (0 = use fixed limit)
        context_value_per_entry: Map<(ContractAddress, u64), u128>,
        // Maximum entries cap (0 = no cap)
        context_max_entries: Map<(ContractAddress, u64), u32>,
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

    // Implement the EntryValidator trait for the contract
    impl EntryRequirementExtensionImplInternal of EntryRequirementExtension<ContractState> {
        fn validate_entry(
            self: @ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            assert!(qualification.len() == 0, "Opus Entry Validator: Qualification data invalid");

            // Single trove pass: covers both threshold check and quota check.
            let threshold = self.context_debt_threshold.read((context_owner, context_id));
            let value_per_entry = self.context_value_per_entry.read((context_owner, context_id));
            let max_entries = self.context_max_entries.read((context_owner, context_id));

            let (total_debt, total_entries_allowed, has_troves) = self
                .collect_player_trove_state(
                    context_owner,
                    context_id,
                    player_address,
                    threshold,
                    value_per_entry,
                    max_entries,
                );

            if !has_troves || total_debt < threshold {
                return false;
            }

            let used_entries = self
                .context_entries_per_address
                .read((context_owner, context_id, player_address));

            if value_per_entry > 0 {
                used_entries < total_entries_allowed
            } else {
                let entry_limit = self.context_entry_limit.read((context_owner, context_id));
                if entry_limit == 0 {
                    return true;
                }
                used_entries < entry_limit
            }
        }

        /// Check if an existing entry should be banned
        /// Returns true if the player's trove no longer meets requirements OR is over quota
        fn should_ban_entry(
            self: @ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            game_token_id: felt252,
            current_owner: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            let threshold = self.context_debt_threshold.read((context_owner, context_id));
            let value_per_entry = self.context_value_per_entry.read((context_owner, context_id));
            let max_entries = self.context_max_entries.read((context_owner, context_id));

            let (total_debt, total_entries_allowed, has_troves) = self
                .collect_player_trove_state(
                    context_owner,
                    context_id,
                    current_owner,
                    threshold,
                    value_per_entry,
                    max_entries,
                );

            if !has_troves || total_debt < threshold {
                return true;
            }

            if value_per_entry > 0 {
                let used_entries = self
                    .context_entries_per_address
                    .read((context_owner, context_id, current_owner));
                return used_entries > total_entries_allowed;
            }

            false
        }

        fn entries_left(
            self: @ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> Option<u32> {
            let value_per_entry = self.context_value_per_entry.read((context_owner, context_id));

            if value_per_entry > 0 {
                let threshold = self.context_debt_threshold.read((context_owner, context_id));
                let max_entries = self.context_max_entries.read((context_owner, context_id));
                let (_, total_entries_allowed, _) = self
                    .collect_player_trove_state(
                        context_owner,
                        context_id,
                        player_address,
                        threshold,
                        value_per_entry,
                        max_entries,
                    );
                let used_entries = self
                    .context_entries_per_address
                    .read((context_owner, context_id, player_address));

                if total_entries_allowed > used_entries {
                    Option::Some(total_entries_allowed - used_entries)
                } else {
                    Option::Some(0)
                }
            } else {
                // Fixed entry limit mode
                let entry_limit = self.context_entry_limit.read((context_owner, context_id));
                if entry_limit == 0 {
                    return Option::None;
                }
                let used_entries = self
                    .context_entries_per_address
                    .read((context_owner, context_id, player_address));
                let remaining_entries = entry_limit - used_entries;
                Option::Some(remaining_entries)
            }
        }

        fn add_config(
            ref self: ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            entry_limit: u32,
            config: Span<felt252>,
        ) {
            // Config format:
            // [0]: asset_count (u8) - 0 = wildcard, N = filter by N assets
            // [1..N]: asset addresses (if asset_count > 0)
            // [N+1]: threshold (u128) - minimum yin debt to qualify
            // [N+2]: value_per_entry (u128) - yin required per entry
            // [N+3]: max_entries (u8) - maximum entries cap (0 = no cap)
            // [N+4]: bannable (bool) - whether entries support banning if debt drops below
            // threshold or exceeds quota

            let asset_count: u8 = (*config.at(0)).try_into().unwrap();
            self.context_asset_count.write((context_owner, context_id), asset_count);

            // Parse asset addresses
            let mut i: u8 = 0;
            loop {
                if i >= asset_count {
                    break;
                }
                let asset_address: ContractAddress = (*config.at((1 + i).into()))
                    .try_into()
                    .unwrap();
                self.context_assets.write((context_owner, context_id, i), asset_address);
                i += 1;
            }

            // Parse remaining config (offset by asset_count)
            let offset: usize = (1 + asset_count).into();
            let threshold: u128 = (*config.at(offset)).try_into().unwrap();
            let value_per_entry: u128 = if config.len() > offset + 1 {
                (*config.at(offset + 1)).try_into().unwrap()
            } else {
                0
            };
            let max_entries: u32 = if config.len() > offset + 2 {
                (*config.at(offset + 2)).try_into().unwrap()
            } else {
                0
            };

            let bannable: bool = if config.len() > offset + 3 {
                (*config.at(offset + 3)) != 0
            } else {
                false
            };

            self.context_debt_threshold.write((context_owner, context_id), threshold);
            self.context_entry_limit.write((context_owner, context_id), entry_limit);
            self.context_value_per_entry.write((context_owner, context_id), value_per_entry);
            self.context_max_entries.write((context_owner, context_id), max_entries);
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
            let current_entries = self.context_entries_per_address.read(key);
            self.context_entries_per_address.write(key, current_entries + 1);
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
            let current_entries = self.context_entries_per_address.read(key);
            if current_entries > 0 {
                self.context_entries_per_address.write(key, current_entries - 1);
            }
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Check if a trove matches the asset filter for a context
        /// Returns true if asset_count=0 (wildcard) or trove contains at least one specified asset
        fn trove_matches_asset_filter(
            self: @ContractState, context_owner: ContractAddress, context_id: u64, trove_id: u64,
        ) -> bool {
            let asset_count = self.context_asset_count.read((context_owner, context_id));

            // Wildcard mode: accept all troves
            if asset_count == 0 {
                return true;
            }

            // Check if trove has any of the specified assets
            let abbot = IAbbotDispatcher { contract_address: abbot_address() };
            let mut i: u8 = 0;
            loop {
                if i >= asset_count {
                    break;
                }

                let asset_address = self.context_assets.read((context_owner, context_id, i));
                let balance = abbot.get_trove_asset_balance(trove_id, asset_address);

                // If trove has this asset, it matches the filter
                if balance > 0 {
                    return true;
                }

                i += 1;
            }

            // No matching assets found
            false
        }

        /// Single source of truth for trove iteration. Walks the player's troves once,
        /// summing debt across filter-matched troves and computing the total entries that
        /// debt would qualify the player for. Used by validate_entry, entries_left, and
        /// should_ban_entry to avoid redundant trove iteration on the hot enter_tournament
        /// path.
        ///
        /// Returns:
        /// - total_debt_wad: aggregated debt across filtered troves (wad units)
        /// - total_entries_capped: entries computed from
        ///   `(total_debt_wad - threshold) / value_per_entry`, capped at `max_entries`. Always
        ///   `0` when `value_per_entry == 0` (fixed-mode); callers must use `context_entry_limit`
        ///   in that case.
        /// - has_troves: false if the player has no troves at all (callers short-circuit).
        fn collect_player_trove_state(
            self: @ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            player_address: ContractAddress,
            threshold: u128,
            value_per_entry: u128,
            max_entries: u32,
        ) -> (u128, u32, bool) {
            let abbot = IAbbotDispatcher { contract_address: abbot_address() };
            let mut user_troves: Span<u64> = abbot.get_user_trove_ids(player_address);

            if user_troves.len() == 0 {
                return (0, 0, false);
            }

            let shrine = IShrineDispatcher { contract_address: shrine_address() };

            // Sum debt across filtered troves (in wad units)
            let mut total_debt: u128 = 0;
            loop {
                match user_troves.pop_front() {
                    Option::Some(trove_id) => {
                        if !self.trove_matches_asset_filter(context_owner, context_id, *trove_id) {
                            continue;
                        }
                        let health: Health = shrine.get_trove_health(*trove_id);
                        total_debt += health.debt.val;
                    },
                    Option::None => { break; },
                }
            }

            // Compute capped entries only when the validator is configured for WAD mode.
            let total_entries_u32: u32 = if value_per_entry > 0 && total_debt > threshold {
                let raw: u128 = (total_debt - threshold) / value_per_entry;
                let mut capped: u32 = match raw.try_into() {
                    Option::Some(val) => val,
                    Option::None => 0,
                };
                if max_entries > 0 && capped > max_entries {
                    capped = max_entries;
                }
                capped
            } else {
                0
            };

            (total_debt, total_entries_u32, true)
        }
    }

    // Public interface implementation
    use super::IOpusTrovesValidator;
    #[abi(embed_v0)]
    impl OpusTrovesValidatorImpl of IOpusTrovesValidator<ContractState> {
        fn get_debt_threshold(
            self: @ContractState, context_owner: ContractAddress, context_id: u64,
        ) -> u128 {
            self.context_debt_threshold.read((context_owner, context_id))
        }

        fn get_value_per_entry(
            self: @ContractState, context_owner: ContractAddress, context_id: u64,
        ) -> u128 {
            self.context_value_per_entry.read((context_owner, context_id))
        }

        fn get_max_entries(
            self: @ContractState, context_owner: ContractAddress, context_id: u64,
        ) -> u32 {
            self.context_max_entries.read((context_owner, context_id))
        }
    }
}
