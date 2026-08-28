use starknet::ContractAddress;

/// A game token id is a PACKED felt, not a counter — the standard game token
/// encodes minted_at, delays, settings_id, minted_by, flags and more into one
/// felt252. A live Budokan v2 token observed on sepolia is 156 bits, so a `u64`
/// here silently truncates.
#[derive(Copy, Drop, Serde)]
pub struct Registration {
    pub game_address: ContractAddress,
    pub game_token_id: felt252,
    pub context_id: u64,
    pub entry_number: u32,
    pub has_submitted: bool,
    pub is_banned: bool,
}

/// Registration queries a host (e.g. Budokan) exposes to extensions.
///
/// Every lookup is keyed by `(game_address, token_id)`, never a bare token id.
/// An id is unique only within the contract that minted it, and a host may run
/// contexts against many games, so a bare id cannot name one context — two
/// games can each hold the same id. Extensions that authorize on the answer
/// (entry-requirement validators qualifying a player by prior participation)
/// would otherwise be griefable by a constructed collision.
#[starknet::interface]
pub trait IRegistration<TState> {
    fn get_registration(
        self: @TState, game_address: ContractAddress, token_id: felt252,
    ) -> Registration;
    fn is_registration_banned(
        self: @TState, game_address: ContractAddress, token_id: felt252,
    ) -> bool;
    fn get_context_id_for_token(
        self: @TState, game_address: ContractAddress, token_id: felt252,
    ) -> u64;
    fn get_entry_count(self: @TState, context_id: u64) -> u32;
    fn registration_exists(self: @TState, game_address: ContractAddress, token_id: felt252) -> bool;
}
