// SPDX-License-Identifier: BUSL-1.1

//! Tournament Validator
//!
//! This extension contract validates tournament entry based on participation/winning
//! in qualifying tournaments. It delegates to the owner contract (which must implement
//! `ITournament` + `IRegistration`) to query registration and leaderboard data.
//!
//! Qualifying Modes:
//! - PER_TOKEN (0): Each qualifying token grants `entry_limit` entries (like a "punch card").
//!   Entries are tracked per token. Transfer-safe without banning.
//! - ALL (1): Must qualify from ALL tournaments. Each qualifying token can back up to
//!   `entry_limit` entries (across all owners); an entry consumes one slot on every
//!   qualifying token in the proof. Quota is keyed by token id, not player address, so
//!   transferring tokens to a fresh wallet cannot grant additional entries.
//!
//! Configuration (via add_config):
//! - config[0]: qualifier_type (0 = participants, 1 = top_position)
//! - config[1]: qualifying_mode (0 = PER_TOKEN, 1 = ALL)
//! - config[2]: top_positions (for QUALIFIER_TYPE_TOP_POSITION: how many top positions count as
//! winners, 0 = all positions)
//! - config[3..]: qualifying tournament IDs
//!
//! Qualification proof (via valid_entry qualification param):
//! For PER_TOKEN mode:
//! - qualification[0]: qualifying tournament ID
//! - qualification[1]: token ID used in qualifying tournament
//! - qualification[2]: position on leaderboard (for top_position type, optional)
//!
//! For ALL mode:
//! For PARTICIPANTS: token IDs in same order as qualifying tournament IDs
//! - qualification[0..n]: token IDs for each qualifying tournament
//! For TOP_POSITION: pairs of (token_id, position) for each qualifying tournament
//! - qualification[0]: token_id_1, qualification[1]: position_1, etc.

use starknet::ContractAddress;

pub const QUALIFIER_TYPE_PARTICIPANTS: felt252 = 0;
pub const QUALIFIER_TYPE_TOP_POSITION: felt252 = 1;

pub const QUALIFYING_MODE_PER_TOKEN: felt252 = 0;
pub const QUALIFYING_MODE_ALL: felt252 = 1;

#[starknet::interface]
pub trait ITournamentValidator<TState> {
    fn get_qualifier_type(
        self: @TState, context_owner: ContractAddress, tournament_id: u64,
    ) -> felt252;
    fn get_qualifying_mode(
        self: @TState, context_owner: ContractAddress, tournament_id: u64,
    ) -> felt252;
    fn get_qualifying_tournament_ids(
        self: @TState, context_owner: ContractAddress, tournament_id: u64,
    ) -> Array<u64>;
    fn get_top_positions(self: @TState, context_owner: ContractAddress, tournament_id: u64) -> u32;
}

#[starknet::contract]
pub mod TournamentValidator {
    use core::num::traits::Zero;
    use metagame_extensions_entry_requirement::entry_requirement_extension_component::EntryRequirementExtensionComponent;
    use metagame_extensions_entry_requirement::entry_requirement_extension_component::EntryRequirementExtensionComponent::EntryRequirementExtension;
    use metagame_extensions_interfaces::registration::{
        IRegistrationDispatcher, IRegistrationDispatcherTrait,
    };
    use metagame_extensions_interfaces::tournament::{
        ITournamentDispatcher, ITournamentDispatcherTrait, Phase,
    };
    use metagame_extensions_presets::entry_requirement::externals::game_components::{
        IMinigameDispatcher, IMinigameDispatcherTrait,
    };
    use openzeppelin_interfaces::erc721::{IERC721Dispatcher, IERC721DispatcherTrait};
    use openzeppelin_introspection::src5::SRC5Component;
    use starknet::ContractAddress;
    use starknet::storage::{
        Map, MutableVecTrait, StorageMapReadAccess, StorageMapWriteAccess, StoragePathEntry,
        StoragePointerReadAccess, Vec, VecTrait,
    };
    use starknet::storage_access::StorePacking;
    use super::{
        QUALIFIER_TYPE_PARTICIPANTS, QUALIFIER_TYPE_TOP_POSITION, QUALIFYING_MODE_ALL,
        QUALIFYING_MODE_PER_TOKEN,
    };

    /// Per-context configuration packed into a single felt252 storage slot:
    ///   bit  0      — qualifier_type  (0 = participants, 1 = top_position)
    ///   bit  1      — qualifying_mode (0 = per_token, 1 = all)
    ///   bits 2..34  — entry_limit  (u32)
    ///   bits 34..66 — top_positions (u32)
    #[derive(Drop, Copy, PartialEq)]
    struct ContextConfig {
        qualifier_type: u8,
        qualifying_mode: u8,
        entry_limit: u32,
        top_positions: u32,
    }

    const TWO_POW_1: u256 = 0x2;
    const TWO_POW_2: u256 = 0x4;
    const TWO_POW_34: u256 = 0x400000000;
    const MASK_1_BIT: u256 = 0x1;
    const MASK_32_BITS: u256 = 0xFFFFFFFF;

    impl ContextConfigStorePacking of StorePacking<ContextConfig, felt252> {
        fn pack(value: ContextConfig) -> felt252 {
            let qt: u256 = value.qualifier_type.into();
            let qm: u256 = value.qualifying_mode.into();
            let el: u256 = value.entry_limit.into();
            let tp: u256 = value.top_positions.into();
            (qt + qm * TWO_POW_1 + el * TWO_POW_2 + tp * TWO_POW_34).try_into().unwrap()
        }

        fn unpack(value: felt252) -> ContextConfig {
            let v: u256 = value.into();
            ContextConfig {
                qualifier_type: (v & MASK_1_BIT).try_into().unwrap(),
                qualifying_mode: ((v / TWO_POW_1) & MASK_1_BIT).try_into().unwrap(),
                entry_limit: ((v / TWO_POW_2) & MASK_32_BITS).try_into().unwrap(),
                top_positions: ((v / TWO_POW_34) & MASK_32_BITS).try_into().unwrap(),
            }
        }
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
        /// Packed config per (context_owner, tournament_id): qualifier_type, qualifying_mode,
        /// entry_limit, and top_positions in a single felt252 slot.
        context_config: Map<(ContractAddress, u64), ContextConfig>,
        /// Qualifying tournament IDs per tournament.
        qualifying_tournament_ids: Map<(ContractAddress, u64), Vec<u64>>,
        /// Entry count per (context_owner, tournament_id, qualifying_token_id). Used by both
        /// PER_TOKEN mode (one slot per entry) and ALL mode (every qualifying token in the
        /// proof gets a slot).
        token_entries: Map<(ContractAddress, u64, u64), u32>,
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
            if context_owner.is_zero() {
                return false;
            }

            let cfg = self.context_config.read((context_owner, context_id));
            let qualifier_type: felt252 = cfg.qualifier_type.into();

            if cfg.qualifying_mode.into() == QUALIFYING_MODE_ALL {
                self
                    .validate_all_tournaments(
                        context_owner,
                        context_id,
                        player_address,
                        qualification,
                        qualifier_type,
                        cfg.entry_limit,
                        cfg.top_positions,
                    )
            } else {
                if !self
                    .validate_single_tournament(
                        context_owner,
                        context_id,
                        player_address,
                        qualification,
                        qualifier_type,
                        cfg.top_positions,
                    ) {
                    return false;
                }
                if cfg.entry_limit == 0 {
                    return true;
                }
                let qualifying_token_id: u64 = (*qualification.at(1)).try_into().unwrap();
                let current_entries = self
                    .token_entries
                    .read((context_owner, context_id, qualifying_token_id));
                current_entries < cfg.entry_limit
            }
        }

        /// Tournament entries should never be banned after registration
        /// The qualification (owning a token from previous tournament) was valid at registration
        fn should_ban_entry(
            self: @ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            game_token_id: felt252,
            current_owner: ContractAddress,
            qualification: Span<felt252>,
        ) -> bool {
            // Never ban tournament entries - they were valid at registration time
            false
        }

        fn entries_left(
            self: @ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) -> Option<u32> {
            if context_owner.is_zero() {
                return Option::Some(0);
            }

            let cfg = self.context_config.read((context_owner, context_id));
            let qualifier_type: felt252 = cfg.qualifier_type.into();
            let is_all = cfg.qualifying_mode.into() == QUALIFYING_MODE_ALL;

            // Validate qualification only — pass entry_limit=0 to skip the inline quota
            // check; we want to compute remaining entries explicitly below.
            let is_valid = if is_all {
                self
                    .validate_all_tournaments(
                        context_owner,
                        context_id,
                        player_address,
                        qualification,
                        qualifier_type,
                        0,
                        cfg.top_positions,
                    )
            } else {
                self
                    .validate_single_tournament(
                        context_owner,
                        context_id,
                        player_address,
                        qualification,
                        qualifier_type,
                        cfg.top_positions,
                    )
            };

            if !is_valid {
                return Option::Some(0);
            }

            if cfg.entry_limit == 0 {
                return Option::None;
            }

            if is_all {
                // Bottleneck: an entry needs a free slot on every qualifying token, so
                // remaining entries = min over tokens of (entry_limit - token_entries).
                let stride: u32 = if qualifier_type == QUALIFIER_TYPE_TOP_POSITION {
                    2
                } else {
                    1
                };
                let mut min_remaining: u32 = cfg.entry_limit;
                let mut i: u32 = 0;
                while i < qualification.len() {
                    let token_id: u64 = (*qualification.at(i)).try_into().unwrap();
                    let used = self.token_entries.read((context_owner, context_id, token_id));
                    let remaining = if used >= cfg.entry_limit {
                        0
                    } else {
                        cfg.entry_limit - used
                    };
                    if remaining < min_remaining {
                        min_remaining = remaining;
                    }
                    i += stride;
                }
                Option::Some(min_remaining)
            } else {
                let qualifying_token_id: u64 = (*qualification.at(1)).try_into().unwrap();
                let current_entries = self
                    .token_entries
                    .read((context_owner, context_id, qualifying_token_id));
                Option::Some(cfg.entry_limit - current_entries)
            }
        }

        fn add_config(
            ref self: ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            entry_limit: u32,
            config: Span<felt252>,
        ) {
            // config[0]: qualifier_type (0 = participants, 1 = top_position)
            // config[1]: qualifying_mode (0 = PER_TOKEN, 1 = ALL)
            // config[2]: top_positions (0 = all positions, or number of top positions for
            // top_position type)
            // config[3..]: qualifying tournament IDs
            assert!(
                config.len() >= 4,
                "Config must have qualifier_type, qualifying_mode, top_positions, and at least one tournament ID",
            );

            let qualifier_type_raw = *config.at(0);
            assert!(
                qualifier_type_raw == QUALIFIER_TYPE_PARTICIPANTS
                    || qualifier_type_raw == QUALIFIER_TYPE_TOP_POSITION,
                "Invalid qualifier type",
            );

            let qualifying_mode_raw = *config.at(1);
            assert!(
                qualifying_mode_raw == QUALIFYING_MODE_PER_TOKEN
                    || qualifying_mode_raw == QUALIFYING_MODE_ALL,
                "Invalid qualifying mode",
            );

            self
                .context_config
                .write(
                    (context_owner, context_id),
                    ContextConfig {
                        qualifier_type: qualifier_type_raw.try_into().unwrap(),
                        qualifying_mode: qualifying_mode_raw.try_into().unwrap(),
                        entry_limit,
                        top_positions: (*config.at(2)).try_into().unwrap(),
                    },
                );

            // Store qualifying tournament IDs
            let mut vec = self.qualifying_tournament_ids.entry((context_owner, context_id));
            let mut i: u32 = 3;
            loop {
                if i >= config.len() {
                    break;
                }
                let qualifying_id: u64 = (*config.at(i)).try_into().unwrap();
                vec.push(qualifying_id);
                i += 1;
            }
        }

        fn on_entry_added(
            ref self: ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            game_token_id: felt252,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) {
            let cfg = self.context_config.read((context_owner, context_id));

            if cfg.qualifying_mode.into() == QUALIFYING_MODE_ALL {
                let stride: u32 = if cfg.qualifier_type.into() == QUALIFIER_TYPE_TOP_POSITION {
                    2
                } else {
                    1
                };
                let mut i: u32 = 0;
                while i < qualification.len() {
                    let token_id: u64 = (*qualification.at(i)).try_into().unwrap();
                    let key = (context_owner, context_id, token_id);
                    self.token_entries.write(key, self.token_entries.read(key) + 1);
                    i += stride;
                }
            } else {
                let qualifying_token_id: u64 = (*qualification.at(1)).try_into().unwrap();
                let key = (context_owner, context_id, qualifying_token_id);
                self.token_entries.write(key, self.token_entries.read(key) + 1);
            }
        }

        fn on_entry_removed(
            ref self: ContractState,
            context_owner: ContractAddress,
            context_id: u64,
            game_token_id: felt252,
            player_address: ContractAddress,
            qualification: Span<felt252>,
        ) {
            let cfg = self.context_config.read((context_owner, context_id));

            if cfg.qualifying_mode.into() == QUALIFYING_MODE_ALL {
                let stride: u32 = if cfg.qualifier_type.into() == QUALIFIER_TYPE_TOP_POSITION {
                    2
                } else {
                    1
                };
                let mut i: u32 = 0;
                while i < qualification.len() {
                    let token_id: u64 = (*qualification.at(i)).try_into().unwrap();
                    let key = (context_owner, context_id, token_id);
                    let current = self.token_entries.read(key);
                    if current > 0 {
                        self.token_entries.write(key, current - 1);
                    }
                    i += stride;
                }
            } else {
                let qualifying_token_id: u64 = (*qualification.at(1)).try_into().unwrap();
                let key = (context_owner, context_id, qualifying_token_id);
                let current_entries = self.token_entries.read(key);
                if current_entries > 0 {
                    self.token_entries.write(key, current_entries - 1);
                }
            }
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        /// Validate ALL-mode qualification and the per-token quota in a single Vec walk.
        /// `entry_limit == 0` skips the quota check (treat as unlimited). Quota is keyed
        /// by qualifying token id, so transferring tokens between wallets cannot grant
        /// additional entries — the same slot is consumed regardless of owner.
        fn validate_all_tournaments(
            self: @ContractState,
            context_owner: ContractAddress,
            tournament_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
            qualifier_type: felt252,
            entry_limit: u32,
            top_positions: u32,
        ) -> bool {
            let vec = self.qualifying_tournament_ids.entry((context_owner, tournament_id));
            let num_tournaments: u32 = vec.len().try_into().unwrap();
            if num_tournaments == 0 {
                return false;
            }

            let expected_len: u32 = if qualifier_type == QUALIFIER_TYPE_TOP_POSITION {
                num_tournaments * 2
            } else {
                num_tournaments
            };
            if qualification.len() != expected_len {
                return false;
            }

            let mut i: u32 = 0;
            loop {
                if i >= num_tournaments {
                    break true;
                }
                let qualifying_tournament_id = vec.at(i.into()).read();
                let (token_id, position): (u64, Option<u8>) =
                    if qualifier_type == QUALIFIER_TYPE_TOP_POSITION {
                    (
                        (*qualification.at(i * 2)).try_into().unwrap(),
                        Option::Some((*qualification.at(i * 2 + 1)).try_into().unwrap()),
                    )
                } else {
                    ((*qualification.at(i)).try_into().unwrap(), Option::None)
                };

                if !self
                    .validate_token_participation(
                        context_owner,
                        qualifying_tournament_id,
                        token_id,
                        player_address,
                        position,
                        qualifier_type,
                        top_positions,
                    ) {
                    break false;
                }

                if entry_limit != 0
                    && self
                        .token_entries
                        .read((context_owner, tournament_id, token_id)) >= entry_limit {
                    break false;
                }

                i += 1;
            }
        }

        /// Validate PER_TOKEN-mode qualification (single qualifying tournament).
        fn validate_single_tournament(
            self: @ContractState,
            context_owner: ContractAddress,
            tournament_id: u64,
            player_address: ContractAddress,
            qualification: Span<felt252>,
            qualifier_type: felt252,
            top_positions: u32,
        ) -> bool {
            // qualification[0]: qualifying tournament id
            // qualification[1]: token id used in qualifying tournament
            // qualification[2]: position on leaderboard (TOP_POSITION only)
            if qualification.len() < 2 {
                return false;
            }

            let qualifying_tournament_id: u64 = (*qualification.at(0)).try_into().unwrap();
            let token_id: u64 = (*qualification.at(1)).try_into().unwrap();

            if !self
                .is_qualifying_tournament(context_owner, tournament_id, qualifying_tournament_id) {
                return false;
            }

            let position: Option<u8> = if qualifier_type == QUALIFIER_TYPE_TOP_POSITION {
                if qualification.len() < 3 {
                    return false;
                }
                Option::Some((*qualification.at(2)).try_into().unwrap())
            } else {
                Option::None
            };

            self
                .validate_token_participation(
                    context_owner,
                    qualifying_tournament_id,
                    token_id,
                    player_address,
                    position,
                    qualifier_type,
                    top_positions,
                )
        }

        /// Verify `player_address` owns `token_id`, that the token is registered in
        /// `qualifying_tournament_id`, and (TOP_POSITION only) that the leaderboard
        /// position is in range. `qualifier_type` and `top_positions` are passed in to
        /// avoid repeated storage reads inside the ALL-mode loop.
        fn validate_token_participation(
            self: @ContractState,
            context_owner: ContractAddress,
            qualifying_tournament_id: u64,
            token_id: u64,
            player_address: ContractAddress,
            position: Option<u8>,
            qualifier_type: felt252,
            top_positions: u32,
        ) -> bool {
            let tournament = ITournamentDispatcher { contract_address: context_owner };
            let registration_dispatcher = IRegistrationDispatcher {
                contract_address: context_owner,
            };

            let qualifying_tournament = tournament.tournament(qualifying_tournament_id);
            let game_address = qualifying_tournament.game_config.address;

            let registration = registration_dispatcher.get_registration(game_address, token_id);
            if registration.entry_number == 0
                || registration.context_id != qualifying_tournament_id {
                return false;
            }

            let game_dispatcher = IMinigameDispatcher { contract_address: game_address };
            let game_token_address = game_dispatcher.token_address();
            let erc721 = IERC721Dispatcher { contract_address: game_token_address };
            let token_owner = erc721.owner_of(token_id.into());

            if token_owner != player_address {
                return false;
            }

            if qualifier_type != QUALIFIER_TYPE_TOP_POSITION {
                return true;
            }

            if tournament.current_phase(qualifying_tournament_id) != Phase::Finalized {
                return false;
            }
            if !registration.has_submitted {
                return false;
            }

            let position = match position {
                Option::Some(p) => p,
                Option::None => { return false; },
            };
            if position == 0 {
                return false;
            }
            if top_positions > 0 && position.into() > top_positions {
                return false;
            }

            let leaderboard = tournament.get_leaderboard(qualifying_tournament_id);
            if position.into() > leaderboard.len() {
                return false;
            }
            let leaderboard_token_id = *leaderboard.at((position - 1).into());
            leaderboard_token_id == token_id
        }

        fn is_qualifying_tournament(
            self: @ContractState,
            context_owner: ContractAddress,
            tournament_id: u64,
            qualifying_tournament_id: u64,
        ) -> bool {
            let vec = self.qualifying_tournament_ids.entry((context_owner, tournament_id));
            let len = vec.len();
            let mut i: u64 = 0;
            loop {
                if i >= len {
                    break false;
                }
                if vec.at(i).read() == qualifying_tournament_id {
                    break true;
                }
                i += 1;
            }
        }
    }

    // Public interface implementation
    use super::ITournamentValidator;
    #[abi(embed_v0)]
    impl TournamentValidatorImpl of ITournamentValidator<ContractState> {
        fn get_qualifier_type(
            self: @ContractState, context_owner: ContractAddress, tournament_id: u64,
        ) -> felt252 {
            self.context_config.read((context_owner, tournament_id)).qualifier_type.into()
        }

        fn get_qualifying_mode(
            self: @ContractState, context_owner: ContractAddress, tournament_id: u64,
        ) -> felt252 {
            self.context_config.read((context_owner, tournament_id)).qualifying_mode.into()
        }

        fn get_qualifying_tournament_ids(
            self: @ContractState, context_owner: ContractAddress, tournament_id: u64,
        ) -> Array<u64> {
            let vec = self.qualifying_tournament_ids.entry((context_owner, tournament_id));
            let len = vec.len();
            let mut arr = ArrayTrait::new();
            let mut i: u64 = 0;
            loop {
                if i >= len {
                    break;
                }
                arr.append(vec.at(i).read());
                i += 1;
            }
            arr
        }

        fn get_top_positions(
            self: @ContractState, context_owner: ContractAddress, tournament_id: u64,
        ) -> u32 {
            self.context_config.read((context_owner, tournament_id)).top_positions
        }
    }
}
