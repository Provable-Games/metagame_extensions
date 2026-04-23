use starknet::ContractAddress;

/// SNIP-5 interface ID derived via src5_rs: XOR of extended function selectors
/// - is_context_registered, bannable, valid_entry, should_ban,
///   entries_left, add_config, add_entry, remove_entry
///
/// Storage on a validator is namespaced by `(context_owner, context_id)`, where
/// `context_owner` is the contract address that first called `add_config` for a
/// given `context_id`. Writes are always performed by the owner (caller); reads
/// take `context_owner` explicitly so external views (frontends, indexers) can
/// disambiguate contexts across different owner contracts.
pub const IENTRY_REQUIREMENT_EXTENSION_ID: felt252 =
    0x41aca80c7cf354c7055a0d77bfb053c4b544a3c9ea9c9f323097394864b616;

#[starknet::interface]
pub trait IEntryRequirementExtension<TState> {
    /// Returns true if `(context_owner, context_id)` has been initialized via `add_config`.
    fn is_context_registered(
        self: @TState, context_owner: ContractAddress, context_id: u64,
    ) -> bool;

    /// Returns true if entries for `(context_owner, context_id)` support banning.
    /// When false, `should_ban` always returns false. When true, the consumer
    /// (e.g. tournament platform) decides when banning may occur.
    fn bannable(self: @TState, context_owner: ContractAddress, context_id: u64) -> bool;

    /// Check if a player's entry is valid for a context (used at registration time)
    fn valid_entry(
        self: @TState,
        context_owner: ContractAddress,
        context_id: u64,
        player_address: ContractAddress,
        qualification: Span<felt252>,
    ) -> bool;

    /// Check if an existing entry should be banned
    /// Returns true if the entry should be banned, false if it should remain valid
    fn should_ban(
        self: @TState,
        context_owner: ContractAddress,
        context_id: u64,
        game_token_id: felt252,
        current_owner: ContractAddress,
        qualification: Span<felt252>,
    ) -> bool;

    /// Check how many entries are left for a player
    fn entries_left(
        self: @TState,
        context_owner: ContractAddress,
        context_id: u64,
        player_address: ContractAddress,
        qualification: Span<felt252>,
    ) -> Option<u32>;

    /// Register configuration for `(caller, context_id)`. A given caller may only
    /// register a given `context_id` once — re-registration reverts.
    fn add_config(ref self: TState, context_id: u64, entry_limit: u32, config: Span<felt252>);

    /// Add an entry for a player in a context
    /// game_token_id is tracked to support per-entry banning decisions.
    /// Caller must be the `context_owner` that previously called `add_config`.
    fn add_entry(
        ref self: TState,
        context_id: u64,
        game_token_id: felt252,
        player_address: ContractAddress,
        qualification: Span<felt252>,
    );

    /// Remove an entry for a player in a context (called when entry is banned)
    /// Caller must be the `context_owner` that previously called `add_config`.
    fn remove_entry(
        ref self: TState,
        context_id: u64,
        game_token_id: felt252,
        player_address: ContractAddress,
        qualification: Span<felt252>,
    );
}
