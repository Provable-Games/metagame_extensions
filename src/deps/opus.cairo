use starknet::ContractAddress;

#[derive(Copy, Drop, PartialEq, Serde)]
pub struct AssetBalance {
    pub address: ContractAddress,
    pub amount: u128,
}
