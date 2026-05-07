use starknet::ContractAddress;

#[starknet::interface]
pub trait IERC20<TContractState> {
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn name(self: @TContractState) -> ByteArray;
    fn symbol(self: @TContractState) -> ByteArray;
    fn decimals(self: @TContractState) -> u8;
}

#[starknet::interface]
pub trait IEntryRequirementExtensionMock<TState> {
    fn get_token_address(
        self: @TState, context_owner: ContractAddress, context_id: u64,
    ) -> ContractAddress;
    fn get_min_threshold(self: @TState, context_owner: ContractAddress, context_id: u64) -> u256;
    fn get_max_threshold(self: @TState, context_owner: ContractAddress, context_id: u64) -> u256;
    fn get_value_per_entry(self: @TState, context_owner: ContractAddress, context_id: u64) -> u256;
    fn get_max_entries(self: @TState, context_owner: ContractAddress, context_id: u64) -> u32;
}

#[starknet::contract]
pub mod ERC20BalanceValidator {
    use metagame_extensions_entry_requirement::entry_requirement_extension_component::EntryRequirementExtensionComponent;
    use metagame_extensions_entry_requirement::entry_requirement_extension_component::EntryRequirementExtensionComponent::EntryRequirementExtension;
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
    use super::{IERC20Dispatcher, IERC20DispatcherTrait};

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
        context_token_address: Map<(ContractAddress, u64), ContractAddress>,
        context_min_threshold: Map<(ContractAddress, u64), u256>,
        context_max_threshold: Map<(ContractAddress, u64), u256>,
        context_entry_limit: Map<(ContractAddress, u64), u32>,
        context_entries_per_address: Map<(ContractAddress, u64, ContractAddress), u32>,
        context_value_per_entry: Map<
            (ContractAddress, u64), u256,
        >, // Token amount required per entry (0 = fixed limit)
        context_max_entries: Map<(ContractAddress, u64), u32> // Maximum entries cap (0 = no cap)
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
            assert!(qualification.len() == 0, "ERC20 Entry Validator: Qualification data invalid");

            // Single-pass: one balance_of fetch covers both threshold and quota checks.
            let value_per_entry = self.context_value_per_entry.read((context_owner, context_id));
            let max_entries = self.context_max_entries.read((context_owner, context_id));

            let (meets_thresholds, total_entries_allowed) = self
                .collect_player_balance_state(
                    context_owner, context_id, player_address, value_per_entry, max_entries,
                );

            if !meets_thresholds {
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

        /// Check if an existing entry should be banned.
        /// Returns true if the player no longer meets the balance band, or has more entries
        /// than their current balance now permits (WAD mode only).
        fn should_ban_entry(
            self: @ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            game_token_id: felt252,
            current_owner: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            let value_per_entry = self.context_value_per_entry.read((context_owner, context_id));
            let max_entries = self.context_max_entries.read((context_owner, context_id));

            let (meets_thresholds, total_entries_allowed) = self
                .collect_player_balance_state(
                    context_owner, context_id, current_owner, value_per_entry, max_entries,
                );

            if !meets_thresholds {
                return true;
            }

            if value_per_entry > 0 {
                let used_entries = self
                    .context_entries_per_address
                    .read((context_owner, context_id, current_owner));
                return used_entries > total_entries_allowed;
            }

            // Fixed-mode: a player can't be over quota (they'd have been blocked at entry time).
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
            let max_entries = self.context_max_entries.read((context_owner, context_id));

            // Run threshold check for both modes so fixed-mode entries_left agrees with
            // validate_entry rejection semantics (matching the WAD-mode realignment).
            let (meets_thresholds, total_entries_allowed) = self
                .collect_player_balance_state(
                    context_owner, context_id, player_address, value_per_entry, max_entries,
                );
            if !meets_thresholds {
                return Option::Some(0);
            }

            let used_entries = self
                .context_entries_per_address
                .read((context_owner, context_id, player_address));

            if value_per_entry > 0 {
                if total_entries_allowed > used_entries {
                    Option::Some(total_entries_allowed - used_entries)
                } else {
                    Option::Some(0)
                }
            } else {
                let entry_limit = self.context_entry_limit.read((context_owner, context_id));
                if entry_limit == 0 {
                    return Option::None; // unlimited entries
                }
                // Saturating subtraction: protects against owner re-config lowering the
                // limit below current used_entries (would otherwise underflow + panic).
                if entry_limit > used_entries {
                    Option::Some(entry_limit - used_entries)
                } else {
                    Option::Some(0)
                }
            }
        }

        fn add_config(
            ref self: ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            entry_limit: u32,
            config: Span<felt252>,
        ) {
            // Config format: [token_address, min_threshold_low, min_threshold_high,
            // max_threshold_low, max_threshold_high, value_per_entry_low, value_per_entry_high,
            // max_entries, bannable]
            let token_address: ContractAddress = (*config.at(0)).try_into().unwrap();

            let min_threshold_low: u128 = (*config.at(1)).try_into().unwrap();
            let min_threshold_high: u128 = (*config.at(2)).try_into().unwrap();
            let min_threshold: u256 = u256 { low: min_threshold_low, high: min_threshold_high };

            let max_threshold_low: u128 = if config.len() > 3 {
                (*config.at(3)).try_into().unwrap()
            } else {
                0
            };
            let max_threshold_high: u128 = if config.len() > 4 {
                (*config.at(4)).try_into().unwrap()
            } else {
                0
            };
            let max_threshold: u256 = u256 { low: max_threshold_low, high: max_threshold_high };

            let value_per_entry_low: u128 = if config.len() > 5 {
                (*config.at(5)).try_into().unwrap()
            } else {
                0
            };
            let value_per_entry_high: u128 = if config.len() > 6 {
                (*config.at(6)).try_into().unwrap()
            } else {
                0
            };
            let value_per_entry: u256 = u256 {
                low: value_per_entry_low, high: value_per_entry_high,
            };

            let max_entries: u32 = if config.len() > 7 {
                (*config.at(7)).try_into().unwrap()
            } else {
                0 // Default to no cap if not provided
            };

            let bannable: bool = if config.len() > 8 {
                (*config.at(8)) != 0
            } else {
                false
            };

            self.context_token_address.write((context_owner, context_id), token_address);
            self.context_min_threshold.write((context_owner, context_id), min_threshold);
            self.context_max_threshold.write((context_owner, context_id), max_threshold);
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
        /// Single source of truth for ERC20 balance evaluation. Reads the per-context
        /// thresholds and the player's `balance_of` once, then returns:
        /// - `meets_thresholds`: balance lies in `[min_threshold, max_threshold]` (max_threshold
        ///   = 0 means "no upper bound").
        /// - `total_entries_allowed`: WAD-mode entries computed as
        ///   `(balance - min_threshold) / value_per_entry`, capped at `max_entries`. Always
        ///   `0` when `value_per_entry == 0`; callers must consult `context_entry_limit` in
        ///   that case.
        ///
        /// Callers pre-read `value_per_entry` and `max_entries` so a single call to
        /// `validate_entry` doesn't double-fetch them across helpers.
        ///
        /// Behavior change: the prior `entries_left` capped at `max_threshold` instead of
        /// rejecting; now any balance > max_threshold yields `meets_thresholds = false`,
        /// matching `validate_entry`'s rejection semantics.
        ///
        /// Overflow handling: when `(balance - min_threshold) / value_per_entry` exceeds u32
        /// the entries count saturates to `u32::MAX`. The subsequent `max_entries` cap then
        /// clamps it to the configured ceiling; uncapped contexts get effectively-unlimited
        /// allowance instead of silently rejecting a maximally-eligible player.
        fn collect_player_balance_state(
            self: @ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            player_address: ContractAddress,
            value_per_entry: u256,
            max_entries: u32,
        ) -> (bool, u32) {
            let token_address = self.context_token_address.read((context_owner, context_id));
            let balance = IERC20Dispatcher { contract_address: token_address }
                .balance_of(player_address);

            let min_threshold = self.context_min_threshold.read((context_owner, context_id));
            if balance < min_threshold {
                return (false, 0);
            }

            let max_threshold = self.context_max_threshold.read((context_owner, context_id));
            if max_threshold > 0 && balance > max_threshold {
                return (false, 0);
            }

            if value_per_entry == 0 {
                return (true, 0);
            }

            // Past the bounds checks balance is in [min_threshold, max_threshold (or ∞)],
            // so effective_balance == balance.
            let total_entries_u256: u256 = (balance - min_threshold) / value_per_entry;
            let mut total_entries: u32 = match total_entries_u256.try_into() {
                Option::Some(val) => val,
                Option::None => 0xffffffff_u32,
            };

            if max_entries > 0 && total_entries > max_entries {
                total_entries = max_entries;
            }

            (true, total_entries)
        }
    }

    // Public interface implementation
    use super::IEntryRequirementExtensionMock;
    #[abi(embed_v0)]
    impl EntryValidatorMockImpl of IEntryRequirementExtensionMock<ContractState> {
        fn get_token_address(
            self: @ContractState, context_owner: ContractAddress, context_id: u64,
        ) -> ContractAddress {
            self.context_token_address.read((context_owner, context_id))
        }

        fn get_min_threshold(
            self: @ContractState, context_owner: ContractAddress, context_id: u64,
        ) -> u256 {
            self.context_min_threshold.read((context_owner, context_id))
        }

        fn get_max_threshold(
            self: @ContractState, context_owner: ContractAddress, context_id: u64,
        ) -> u256 {
            self.context_max_threshold.read((context_owner, context_id))
        }

        fn get_value_per_entry(
            self: @ContractState, context_owner: ContractAddress, context_id: u64,
        ) -> u256 {
            self.context_value_per_entry.read((context_owner, context_id))
        }

        fn get_max_entries(
            self: @ContractState, context_owner: ContractAddress, context_id: u64,
        ) -> u32 {
            self.context_max_entries.read((context_owner, context_id))
        }
    }
}
