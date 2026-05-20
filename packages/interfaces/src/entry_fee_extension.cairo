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
// Regenerated via src5_rs after the trait change (recipient dropped,
// position -> token_id). Extended function selectors:
//   is_context_registered(ContractAddress,u64)->E((),())
//     -> 0x1bd720a7b1f7c926b9642d87cfaca619334de1b1cf76338d7520a9c08adea59
//   set_entry_fee_config(u64,(@Array<felt252>))
//     -> 0xdcc8540a5b2d29d9b8f1f762605e7e0711bf2f851821f08579bfd3fa17457a
//   pay_entry_fee(u64,(@Array<felt252>))
//     -> 0x157f02e782eb6de309ce1c9ed797e2d2c20b6b32e2a7ea976ae94d35883d6f6
//   payout_entry_fee(u64,E(felt252,()),(@Array<felt252>))
//     -> 0x2e080fa6f4757a38ed8a57919ffc7fc435618eadae8f30f6b87708dd5d2d1af
//   get_config(ContractAddress,u64)->(@Array<felt252>)
//     -> 0x3f13e92f2c274458cf13cd7bea27853394c6fdfb25228f5ba9e9eaedc9a382e
pub const IENTRY_FEE_EXTENSION_ID: felt252 =
    0x127f41894efc483809bcb4854be559dc21fa0b2df7fe79bf59ccfbfa3719054;

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
