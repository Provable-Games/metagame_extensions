use starknet::ContractAddress;

/// SNIP-5 interface ID for `IPrizeExtension`. Derived via `src5_rs` as the
/// XOR of the Starknet selectors of the four functions listed in the trait
/// below (`is_context_registered`, `add_prize`, `payout_prize`, `get_config`),
/// reflecting the full current surface including the `recipient` and
/// `position` parameters on `payout_prize`.
///
/// Storage is namespaced by `(context_owner, context_id)` where `context_owner`
/// is the contract that first called `add_prize` for that `context_id`.
///
/// REGENERATION: whenever any function signature on the trait below changes
/// (add/remove function, rename, or alter parameter list), this ID MUST be
/// recomputed:
///   1. Copy the trait into a scratch file with `<TState>` stripped (so
///      `fn foo(self: @TState, ...)` becomes `fn foo(self: @State, ...)`)
///      because `src5_rs` cannot resolve generic self types.
///   2. Run `src5_rs parse <scratch_file>` and paste the resulting felt
///      below.
///   3. Update any host SRC5 advertisements (e.g. budokan's
///      `_register_supported_interfaces`).
pub const IPRIZE_EXTENSION_ID: felt252 =
    0x2187266a58431bcbd583ba71c091289eb91506d4fcf6d8d30fbaeabf69ee871;

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

    /// Transfer the escrowed asset at `(caller, context_id, prize_id, position)`
    /// to `recipient`. The host computes `recipient` — either the
    /// leaderboard winner (normal payout) or the original sponsor (refund
    /// when no winner qualifies) — and the extension is just an asset
    /// manager that executes the transfer. Extensions MUST NOT branch on
    /// who the recipient is or query host state to decide; that's a
    /// host-level concern.
    ///
    /// `position` is the 1-indexed leaderboard slot when the prize is
    /// positional (e.g. NFTPrize allocates per-position escrow). For
    /// non-positional prize extensions (whole-pool raffle, dao
    /// distribution, etc.) the host passes `Option::None`. Implementors
    /// that require positional payouts MUST panic on `None`; implementors
    /// that don't use positions MUST ignore the value.
    ///
    /// `payout_params` is extension-defined for any additional metadata
    /// the extension needs to identify exactly what to transfer beyond
    /// `(prize_id, position)`. Most positional extensions leave it empty.
    ///
    /// Extensions MUST mark `(prize_id, position)` as paid (or whatever
    /// uniquely identifies the slot) to prevent double-payout. The host
    /// does NOT track per-position payout state for extensions — that's
    /// the extension's responsibility.
    ///
    /// Caller must be the owner that previously called `add_prize` for this context.
    fn payout_prize(
        ref self: TState,
        context_id: u64,
        prize_id: u64,
        position: Option<u32>,
        recipient: ContractAddress,
        payout_params: Span<felt252>,
    );

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
