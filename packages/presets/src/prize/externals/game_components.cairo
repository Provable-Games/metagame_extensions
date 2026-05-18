use starknet::ContractAddress;

/// Minimal subset of `IMinigame` the prize presets call. Defined locally to
/// keep `metagame_extensions_presets` independent of the full
/// `game_components_interfaces` package.
#[starknet::interface]
pub trait IMinigame<TState> {
    fn token_address(self: @TState) -> ContractAddress;
}

/// Minimal subset of `ILeaderboard`. Hosts that integrate the
/// `LeaderboardComponent` (e.g. Budokan) implement this trait. `get_entries`
/// returns the leaderboard slots in ranked order — `entries[position - 1]`
/// is the `token_id` at 1-indexed `position`.
#[derive(Drop, Copy, Serde)]
pub struct LeaderboardEntry {
    pub token_id: felt252,
    pub score: u64,
}

#[starknet::interface]
pub trait ILeaderboard<TState> {
    fn get_entries(self: @TState, context_id: u64) -> Array<LeaderboardEntry>;
    fn get_leaderboard_length(self: @TState, context_id: u64) -> u32;
}
