use starknet::ContractAddress;

/// SNIP-5 interface ID derived via src5_rs: XOR of extended function selectors
/// - is_context_registered, set_entry_fee_config, pay_entry_fee,
///   payout_entry_fee, get_config
///
/// Storage is namespaced by `(context_owner, context_id)` where `context_owner`
/// is the contract that first called `set_entry_fee_config` for that `context_id`.
///
/// NOTE: this ID is regenerated whenever the trait surface changes. Run
/// `src5_rs parse` against the current trait (with the `<TState>` generic
/// removed so the tool can compute) to regenerate after any change.
// TODO: regenerate via src5_rs after the trait change (recipient dropped,
// position -> token_id).
pub const IENTRY_FEE_EXTENSION_ID: felt252 =
    0x1e982b6c4bfd4c1100d99f1bd74c95da47e1b98efb31515d7058f69b64c470b;

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

    /// Dispatch a fee-pool payout for `(caller, context_id)` keyed by
    /// `token_id`. The extension is fully sovereign on recipient
    /// resolution, eligibility checks, and asset transfer — the host
    /// is a pure dispatcher.
    ///
    /// `token_id`:
    /// - `Some(id)` — the game token claiming this share. The
    ///   extension typically derives the recipient via
    ///   `IERC721::owner_of(token_id)` (or any token-keyed scheme it
    ///   chooses) and uses `id` as the dedupe key.
    /// - `None` — non-claim flows (sponsor refund, creator share,
    ///   dao distribution). The extension MUST encode whatever it
    ///   needs to resolve the recipient in `claim_params`.
    ///
    /// `claim_params` is extension-defined. For token-keyed claims
    /// it's typically empty; for non-token-keyed flows it carries
    /// proofs, slot indices, merkle witnesses, etc.
    ///
    /// Extensions MUST track their own dedupe state so the same
    /// logical claim cannot be replayed. The host does NOT track
    /// per-token-id payout state for extensions.
    ///
    /// Caller must be the owner that previously called `set_entry_fee_config`.
    fn payout_entry_fee(
        ref self: TState, context_id: u64, token_id: Option<felt252>, claim_params: Span<felt252>,
    );

    /// Return the original `config` blob the host passed to
    /// `set_entry_fee_config` for `(context_owner, context_id)`.
    /// Implementors MUST re-serialize whatever they stored back to the
    /// original `Span<felt252>` shape so host viewers (frontends, indexer
    /// RPC fallbacks) can render extension entry-fee configs uniformly
    /// without per-extension knowledge of internal storage layouts.
    /// Returns an empty span when `(context_owner, context_id)` is unknown.
    ///
    /// Read-only view: takes explicit `context_owner` so external callers
    /// (viewers, indexer RPC fallbacks) can query without needing to be
    /// the registered owner.
    fn get_config(self: @TState, context_owner: ContractAddress, context_id: u64) -> Span<felt252>;
}
