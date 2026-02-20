use starknet::ContractAddress;

pub const IENTRY_REQUIREMENT_EXTENSION_ID: felt252 =
    0x03932b83d6f280c123c10e3eec69c9f5776a2a1de7b7d401120c49a9936954fa;

/// Legacy interface IDs for backward compatibility with deployed Budokan contracts.
/// LEGACY_IENTRY_VALIDATOR_ID_V2: from when the trait used `tournament_id` / `game_token_id: u64`.
/// LEGACY_IENTRY_VALIDATOR_ID_V1: from when the trait used `budokan_address` instead of
/// `owner_address`.
pub const LEGACY_IENTRY_VALIDATOR_ID_V2: felt252 =
    0x73b204ef90f88bbdf6a178473d1445e76fd9a48a188c6659cb93f988b8458a;
pub const LEGACY_IENTRY_VALIDATOR_ID_V1: felt252 =
    0x01158754d5cc62137c4de2cbd0e65cbd163990af29f0182006f26fe0cac00bb6;

#[starknet::interface]
pub trait IEntryRequirementExtension<TState> {
    /// Get the owner contract address (e.g., budokan, quest manager)
    fn owner_address(self: @TState) -> ContractAddress;

    /// Returns true if this validator only validates during registration period
    fn registration_only(self: @TState) -> bool;

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
    ) -> Option<u8>;

    /// Add configuration for a context
    fn add_config(ref self: TState, context_id: u64, entry_limit: u8, config: Span<felt252>);

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
