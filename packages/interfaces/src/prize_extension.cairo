use starknet::ContractAddress;

/// SNIP-5 interface ID derived via src5_rs: XOR of extended function selectors
/// - is_context_registered, add_prize, claim_prize
///
/// Storage is namespaced by `(context_owner, context_id)` where `context_owner`
/// is the contract that first called `add_prize` for that `context_id`.
pub const IPRIZE_EXTENSION_ID: felt252 =
    0x3f058684a2de48c9135820c54730c368696c0b35df75942716d0d6537d18bac;

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
}
