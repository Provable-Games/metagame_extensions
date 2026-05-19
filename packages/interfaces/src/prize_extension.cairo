use starknet::ContractAddress;

/// SNIP-5 interface ID derived via src5_rs: XOR of extended function selectors
/// - is_context_registered, add_prize, claim_prize, get_config
///
/// Storage is namespaced by `(context_owner, context_id)` where `context_owner`
/// is the contract that first called `add_prize` for that `context_id`.
///
/// NOTE: this ID is regenerated whenever the trait surface changes. The
/// previous value (with only is_context_registered/add_prize/claim_prize)
/// was 0x3f058684a2de48c9135820c54730c368696c0b35df75942716d0d6537d18bac;
/// run `src5_rs` against the current trait to regenerate after any change.
pub const IPRIZE_EXTENSION_ID: felt252 =
    0x12a5f38bd1e9397d6ca0151207457b6a54ae1f5e750719d6d0a3afde2ca827e;

#[starknet::interface]
pub trait IPrizeExtension<TState> {
    /// Returns true if `(context_owner, context_id)` has been initialized via `add_prize`.
    fn is_context_registered(
        self: @TState, context_owner: ContractAddress, context_id: u64,
    ) -> bool;

    /// Add a prize configuration for `(caller, context_id)`.
    /// First call registers the caller as owner of that context_id on this contract.
    /// Subsequent calls from the same caller may add more prizes, but a different
    /// caller cannot add prizes to an already-registered context.
    fn add_prize(ref self: TState, context_id: u64, prize_id: u64, config: Span<felt252>);

    /// Claim a prize for a context.
    /// Caller must be the owner that previously called `add_prize` for this context.
    fn claim_prize(ref self: TState, context_id: u64, claim_params: Span<felt252>);

    /// Return the original `config` blob the host passed to `add_prize`
    /// for this `(context_owner, context_id, prize_id)`. Implementors
    /// MUST re-serialize whatever they stored back to the original
    /// `Span<felt252>` shape so host viewers / indexer RPC fallbacks
    /// can render extension prizes uniformly without per-extension
    /// knowledge of internal storage layouts. Returns an empty span
    /// when the prize is unknown.
    ///
    /// Read-only view: takes explicit `context_owner` so external
    /// callers (viewers, indexer RPC fallbacks) can query without
    /// needing to be the registered owner.
    fn get_config(
        self: @TState, context_owner: ContractAddress, context_id: u64, prize_id: u64,
    ) -> Span<felt252>;
}
