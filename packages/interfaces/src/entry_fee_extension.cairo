use starknet::ContractAddress;

/// SNIP-5 interface ID derived via src5_rs: XOR of extended function selectors
/// - is_context_registered, set_entry_fee_config, pay_entry_fee, claim_entry_fee
///
/// Storage is namespaced by `(context_owner, context_id)` where `context_owner`
/// is the contract that first called `set_entry_fee_config` for that `context_id`.
pub const IENTRY_FEE_EXTENSION_ID: felt252 =
    0x15632998253d785958f8ca6392be14057aba5032e9b1ae9e779e0ed9f2307f3;

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

    /// Claim entry fee for a context.
    /// Caller must be the owner that previously called `set_entry_fee_config`.
    fn claim_entry_fee(ref self: TState, context_id: u64, claim_params: Span<felt252>);
}
