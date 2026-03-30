use starknet::ContractAddress;

pub const IPRIZE_EXTENSION_ID: felt252 =
    0x02e7351c43ff3a80ab04f2fb889cd9bc0b885243574fb5db3e5fa4a9bca3f332;

/// Legacy interface ID from when the trait used single `owner_address()`.
pub const LEGACY_IPRIZE_EXTENSION_ID: felt252 =
    0x81dddaf0108625e748615f819e4dd9c9ef6bc6fa5386be1520440780699de0;

#[starknet::interface]
pub trait IPrizeExtension<TState> {
    /// Get the owner contract address for a specific context
    fn context_owner(self: @TState, context_id: u64) -> ContractAddress;

    /// Add a prize configuration for a context
    fn add_prize(ref self: TState, context_id: u64, prize_id: u64, config: Span<felt252>);

    /// Claim a prize for a context
    fn claim_prize(ref self: TState, context_id: u64, claim_params: Span<felt252>);
}
