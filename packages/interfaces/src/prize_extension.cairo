use starknet::ContractAddress;

/// SNIP-5 interface ID for `IPrizeExtension`. Derived via `src5_rs` as the
/// XOR of the Starknet selectors of the four functions on the trait below
/// (`is_context_registered`, `add_prize`, `payout_prize`, `get_config`).
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
// Regenerated via src5_rs after the trait change (recipient dropped,
// position -> token_id). Extended function selectors:
//   is_context_registered(ContractAddress,u64)->E((),())
//     -> 0x1bd720a7b1f7c926b9642d87cfaca619334de1b1cf76338d7520a9c08adea59
//   add_prize(u64,u64,(@Array<felt252>))
//     -> 0x2e2c4fca53b00f6e879e79a8ed547a632475ca8d7f4d49bf35519ff0d0d47e8
//   payout_prize(u64,u64,E(felt252,()),(@Array<felt252>))
//     -> 0x3e5a0ae816455e7afa3dae8774b2f0045ed6ba60725b9c9471d0257f6175a1e
//   get_config(ContractAddress,u64,u64)->(@Array<felt252>)
//     -> 0x2da0750f733771b47ff835d74075b8023dc2146baa728df1c673798d51b09d2
pub const IPRIZE_EXTENSION_ID: felt252 =
    0x2601108a8735e986bb3fcf7f163f947c742c853768126b57f7d26ac26acfe7d;

#[starknet::interface]
pub trait IPrizeExtension<TState> {
    /// Returns true if `(context_owner, context_id)` has been initialized via `add_prize`.
    fn is_context_registered(
        self: @TState, context_owner: ContractAddress, context_id: u64,
    ) -> bool;

    /// Add a prize configuration for `(caller, context_id, prize_id)`.
    /// First call registers the caller as owner of that context_id on this contract.
    /// Subsequent calls from the same caller may add more prizes; a different
    /// caller cannot add prizes to an already-registered context.
    fn add_prize(ref self: TState, context_id: u64, prize_id: u64, config: Span<felt252>);

    /// Dispatch a payout for `(caller, context_id, prize_id)` keyed by
    /// `token_id`. The extension is fully sovereign on recipient
    /// resolution, eligibility checks, and asset transfer — the host
    /// is a pure dispatcher.
    ///
    /// `token_id`:
    /// - `Some(id)` — the game token claiming this prize. The
    ///   extension typically derives the recipient via
    ///   `IERC721::owner_of(token_id)` (or any token-keyed scheme it
    ///   chooses).
    /// - `None` — non-claim flows (sponsor refund, dao distribution,
    ///   raffle draw). The extension MUST encode whatever it needs to
    ///   resolve the recipient in `payout_params` (e.g. a refund-slot
    ///   index, a random seed, a list of payees).
    ///
    /// `payout_params` is extension-defined. For token-keyed claims
    /// it's typically empty; for non-positional / non-token-keyed
    /// flows it carries proofs, slot indices, merkle witnesses, etc.
    ///
    /// Extensions MUST track their own dedupe state — usually keyed
    /// by `(prize_id, token_id)` for the claim path and by whatever
    /// the refund flow uses for `payout_params`. The host does NOT
    /// track per-token-id payout state for extensions.
    ///
    /// Caller must be the owner that previously called `add_prize` for this context.
    fn payout_prize(
        ref self: TState,
        context_id: u64,
        prize_id: u64,
        token_id: Option<felt252>,
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
