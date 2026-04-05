use starknet::ContractAddress;

/// SNIP-5 interface ID derived via src5_rs: XOR of extended function selectors
/// - context_owner, set_entry_fee_config, pay_entry_fee, claim_entry_fee
pub const IENTRY_FEE_EXTENSION_ID: felt252 =
    0x13463d1e98ea3e2e0572acfd49f44feb703761ba29a29bae1957b0c387b82e9;

#[starknet::interface]
pub trait IEntryFeeExtension<TState> {
    /// Get the owner contract address for a specific context
    fn context_owner(self: @TState, context_id: u64) -> ContractAddress;

    /// Set entry fee configuration for a context (called during setup)
    fn set_entry_fee_config(ref self: TState, context_id: u64, config: Span<felt252>);

    /// Pay entry fee for a context (called during deposit via extension)
    fn pay_entry_fee(ref self: TState, context_id: u64, pay_params: Span<felt252>);

    /// Claim entry fee for a context
    fn claim_entry_fee(ref self: TState, context_id: u64, claim_params: Span<felt252>);
}
