use starknet::ContractAddress;

/// SNIP-5 interface ID derived via src5_rs: XOR of extended function selectors
/// - context_owner, add_prize, claim_prize
pub const IPRIZE_EXTENSION_ID: felt252 =
    0x392092021f090ebe4ed2465b9c7a988663e13abd1f66a117781968490890eb6;

#[starknet::interface]
pub trait IPrizeExtension<TState> {
    /// Get the owner contract address for a specific context
    fn context_owner(self: @TState, context_id: u64) -> ContractAddress;

    /// Add a prize configuration for a context
    fn add_prize(ref self: TState, context_id: u64, prize_id: u64, config: Span<felt252>);

    /// Claim a prize for a context
    fn claim_prize(ref self: TState, context_id: u64, claim_params: Span<felt252>);
}
