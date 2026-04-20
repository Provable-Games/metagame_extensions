use starknet::ContractAddress;

/// SNIP-5 interface ID derived via src5_rs: XOR of extended function selectors
/// - context_owner, bannable, valid_entry, should_ban,
///   entries_left, add_config, add_entry, remove_entry
pub const IENTRY_REQUIREMENT_EXTENSION_ID: felt252 =
    0x3ea6fd42387b3e499064d9d583d9a60e40bdcbb2e4db3ce82bd980e4e6c7605;

#[starknet::interface]
pub trait IEntryRequirementExtension<TState> {
    /// Get the owner contract address for a specific context
    fn context_owner(self: @TState, context_id: u64) -> ContractAddress;

    /// Returns true if entries in this context can be banned mid-tournament
    fn bannable(self: @TState, context_id: u64) -> bool;

    /// Check if a player's entry is valid for a context (used at registration time)
    fn valid_entry(
        self: @TState,
        context_id: u64,
        player_address: ContractAddress,
        qualification: Span<felt252>,
    ) -> bool;

    /// Check if an existing entry should be banned
    /// Returns true if the entry should be banned, false if it should remain valid
    fn should_ban(
        self: @TState,
        context_id: u64,
        game_token_id: felt252,
        current_owner: ContractAddress,
        qualification: Span<felt252>,
    ) -> bool;

    /// Check how many entries are left for a player
    fn entries_left(
        self: @TState,
        context_id: u64,
        player_address: ContractAddress,
        qualification: Span<felt252>,
    ) -> Option<u32>;

    /// Add configuration for a context
    fn add_config(ref self: TState, context_id: u64, entry_limit: u32, config: Span<felt252>);

    /// Add an entry for a player in a context
    /// game_token_id is tracked to support per-entry banning decisions
    fn add_entry(
        ref self: TState,
        context_id: u64,
        game_token_id: felt252,
        player_address: ContractAddress,
        qualification: Span<felt252>,
    );

    /// Remove an entry for a player in a context (called when entry is banned)
    fn remove_entry(
        ref self: TState,
        context_id: u64,
        game_token_id: felt252,
        player_address: ContractAddress,
        qualification: Span<felt252>,
    );
}
