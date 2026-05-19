use starknet::ContractAddress;

/// Minimal subset of `IMinigame` the prize presets call. Defined locally to
/// keep `metagame_extensions_presets` independent of the full
/// `game_components_interfaces` package.
#[starknet::interface]
pub trait IMinigame<TState> {
    fn token_address(self: @TState) -> ContractAddress;
}

/// Minimal subset of `ILeaderboard`. Hosts that integrate the
/// `LeaderboardComponent` (e.g. Budokan) implement this trait.
/// `get_leaderboard_entry(context_id, position)` returns the `token_id`
/// (and live score) at the 1-indexed `position` in O(1) — preferred
/// over the canonical `get_entries` for per-position lookups since it
/// avoids serializing the full leaderboard.
///
/// Field names mirror the canonical interface (`id` not `token_id`)
/// so Serde decodes cross-contract responses without reordering.
#[derive(Drop, Copy, Serde)]
pub struct LeaderboardEntry {
    pub id: felt252,
    pub score: u64,
}

#[starknet::interface]
pub trait ILeaderboard<TState> {
    fn get_leaderboard_length(self: @TState, context_id: u64) -> u32;
    fn get_leaderboard_entry(self: @TState, context_id: u64, position: u32) -> LeaderboardEntry;
}
