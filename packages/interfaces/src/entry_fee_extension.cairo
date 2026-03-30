use starknet::ContractAddress;

pub const IENTRY_FEE_EXTENSION_ID: felt252 =
    0x016643b9820ae14c6a2aa278edf6bc97c77ffb0b90363fecd95b412a836b0fc9;

/// Legacy interface ID from when the trait used single `owner_address()`.
pub const LEGACY_IENTRY_FEE_EXTENSION_ID: felt252 =
    0x03a74a2500216692acc4a3ecbbe1fd617144b136f0233258752183a06a68beba;

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
