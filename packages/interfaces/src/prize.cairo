use metagame_extensions_interfaces::distribution::Distribution;
use starknet::ContractAddress;

#[derive(Drop, Serde)]
pub struct ERC20Data {
    pub amount: u128,
    pub distribution: Option<Distribution>,
    pub distribution_count: Option<u32>,
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct ERC721Data {
    pub id: u128,
}

#[allow(starknet::store_no_default_variant)]
#[derive(Drop, Serde)]
pub enum TokenTypeData {
    erc20: ERC20Data,
    erc721: ERC721Data,
}

#[derive(Drop, Serde)]
pub struct Prize {
    pub id: u64,
    pub context_id: u64,
    pub token_address: ContractAddress,
    pub token_type: TokenTypeData,
    pub sponsor_address: ContractAddress,
}

#[allow(starknet::store_no_default_variant)]
#[derive(Copy, Drop, Serde, PartialEq)]
pub enum PrizeType {
    Single: u64,
    Distributed: (u64, u32),
}

#[starknet::interface]
pub trait IPrize<TState> {
    fn get_prize(self: @TState, prize_id: u64) -> Prize;
    fn get_total_prizes(self: @TState) -> u64;
    fn is_prize_claimed(self: @TState, context_id: u64, prize_type: PrizeType) -> bool;
}
