use starknet::ContractAddress;

/// SNIP-5 interface ID derived via src5_rs: XOR of extended function selectors
/// - is_context_registered, set_entry_fee_config, pay_entry_fee, payout_entry_fee
///
/// Storage is namespaced by `(context_owner, context_id)` where `context_owner`
/// is the contract that first called `set_entry_fee_config` for that `context_id`.
///
/// NOTE: this ID is regenerated whenever the trait surface changes. Run
/// `src5_rs parse` against the current trait (with the `<TState>` generic
/// removed so the tool can compute) to regenerate after any change.
pub const IENTRY_FEE_EXTENSION_ID: felt252 =
    0x218bc24367da0849cfca52603d6b10e9d3274475de13de06d9b11c76ad67f25;

#[starknet::interface]
pub trait IEntryFeeExtension<TState> {
    /// Returns true if `(context_owner, context_id)` has been initialized
    /// via `set_entry_fee_config`.
    fn is_context_registered(
        self: @TState, context_owner: ContractAddress, context_id: u64,
    ) -> bool;

    /// Register entry fee configuration for `(caller, context_id)` (called during setup).
    /// A given caller may only register a given `context_id` once.
    fn set_entry_fee_config(ref self: TState, context_id: u64, config: Span<felt252>);

    /// Pay entry fee for a context (called during deposit via extension).
    /// Caller must be the owner that previously called `set_entry_fee_config`.
    fn pay_entry_fee(ref self: TState, context_id: u64, pay_params: Span<felt252>);

    /// Transfer the appropriate slice of the fee pool to `recipient`. The
    /// host (e.g. budokan) computes recipient and passes it through —
    /// when `position` is `Some(N)` the host has already validated that
    /// `recipient` matches the leaderboard winner at position N (or the
    /// recorded sponsor when the position has no qualifying entry).
    /// When `position` is `None` the host doesn't validate recipient;
    /// the extension is responsible for any eligibility logic it cares
    /// about via `claim_params`.
    ///
    /// Extensions MUST scope their dedupe by
    /// `(context_owner, context_id, recipient, position, claim_params)`
    /// — or whatever subset of those uniquely identifies a slot — so
    /// the same logical claim cannot be replayed.
    ///
    /// Caller must be the owner that previously called `set_entry_fee_config`.
    fn payout_entry_fee(
        ref self: TState,
        context_id: u64,
        recipient: ContractAddress,
        position: Option<u32>,
        claim_params: Span<felt252>,
    );
}
