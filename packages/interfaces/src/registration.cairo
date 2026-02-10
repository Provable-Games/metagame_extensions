use starknet::ContractAddress;

#[derive(Copy, Drop, Serde)]
pub struct Registration {
    pub game_address: ContractAddress,
    pub game_token_id: u64,
    pub context_id: u64,
    pub entry_number: u32,
    pub has_submitted: bool,
    pub is_banned: bool,
}

#[starknet::interface]
pub trait IRegistration<TState> {
    fn get_registration(
        self: @TState, game_address: ContractAddress, token_id: u64,
    ) -> Registration;
    fn is_registration_banned(self: @TState, game_address: ContractAddress, token_id: u64) -> bool;
    fn get_context_id_for_token(self: @TState, game_address: ContractAddress, token_id: u64) -> u64;
    fn get_entry_count(self: @TState, context_id: u64) -> u32;
    fn registration_exists(self: @TState, game_address: ContractAddress, token_id: u64) -> bool;
}
