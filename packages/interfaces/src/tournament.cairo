//! Minimal read surface of the deployed Budokan needed by the
//! `TournamentValidator` entry-requirement extension.
//!
//! Budokan embeds the game-components v1.1.10 component ABIs. The validator
//! resolves a qualifying game token exactly the way Budokan's OWN code does:
//!   - token -> tournament (context) via `context_details(token_id).id`
//!     (public mirror of `registration._get_token_context(token_id)`)
//!   - token -> leaderboard position via `get_position(context_id, token_id)`
//!     (public mirror of the leaderboard's `get_token_position`)
//!   - qualifying tournament's game contract via
//!     `get_config(context_id).game_address` (the leaderboard config Budokan
//!     writes at tournament creation)
//!   - tournament lifecycle via `current_phase(tournament_id)`
//!
//! All of these selectors are exposed by Budokan (`IBudokan` +
//! `ILeaderboard` + `IMetagameContextDetails`), so a single dispatcher against
//! the Budokan address can read them all.

use starknet::ContractAddress;

// ==============================================
// PHASE (mirrors budokan_interfaces::budokan::Phase)
// ==============================================

#[derive(Copy, Drop, Serde, PartialEq)]
pub enum Phase {
    Scheduled,
    Registration,
    Staging,
    Live,
    Submission,
    Finalized,
}

// ==============================================
// LEADERBOARD CONFIG (mirrors game_components leaderboard LeaderboardStoreConfig)
// ==============================================

#[derive(Copy, Drop, Serde)]
pub struct LeaderboardStoreConfig {
    pub max_entries: u32,
    pub ascending: bool,
    pub game_address: ContractAddress,
}

// ==============================================
// METAGAME CONTEXT (mirrors game_components GameContextDetails)
// ==============================================

#[derive(Drop, Serde, Copy, Clone)]
pub struct GameContext {
    pub name: felt252,
    pub value: felt252,
}

#[derive(Drop, Serde, Clone)]
pub struct GameContextDetails {
    pub name: ByteArray,
    pub description: ByteArray,
    pub id: Option<u32>,
    pub context: Span<GameContext>,
}

// ==============================================
// INTERFACE
// ==============================================

/// Combined read dispatcher for the Budokan contract. Each method dispatches
/// by selector to Budokan's embedded component impls:
///   - `current_phase`   -> `IBudokan`
///   - `get_config`      -> `ILeaderboard`
///   - `get_position`    -> `ILeaderboard`
///   - `context_details` -> `IMetagameContextDetails`
#[starknet::interface]
pub trait IBudokanValidatorReads<TState> {
    /// Tournament lifecycle phase.
    fn current_phase(self: @TState, tournament_id: u64) -> Phase;
    /// Leaderboard config for a context; `game_address` is the qualifying
    /// tournament's game contract (used to resolve the ERC721 for ownership).
    fn get_config(self: @TState, context_id: u64) -> LeaderboardStoreConfig;
    /// 1-indexed leaderboard position of `token_id` in `context_id`, or
    /// `None` if the token has not placed (i.e. never submitted a score).
    fn get_position(self: @TState, context_id: u64, token_id: felt252) -> Option<u32>;
    /// Metagame context details for a game token; `id` is `Some(tournament_id)`
    /// the token is registered in, or `Some(0)`/`None` when unregistered.
    fn context_details(self: @TState, token_id: felt252) -> GameContextDetails;
}
