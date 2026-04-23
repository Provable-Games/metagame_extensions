use starknet::ContractAddress;

// ==============================================
// GOVERNANCE CONTRACT ADDRESSES
// ==============================================

// Governance token contract address on mainnet
pub fn governance_token_address() -> ContractAddress {
    0x042dd777885ad2c116be96d4d634abc90a26a790ffb5871e037dd5ae7d2ec86b.try_into().unwrap()
}

// Governor contract address on mainnet
pub fn governor_address() -> ContractAddress {
    0x050897ea9df71b661b8eac53162be37552e729ee9d33a6f9ae0b61c95a11209e.try_into().unwrap()
}

// ==============================================
// ERC20 TOKEN ADDRESSES
// ==============================================

// ETH token contract address on mainnet (Starknet ETH)
pub fn eth_token_address() -> ContractAddress {
    0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7.try_into().unwrap()
}

// STRK token contract address on mainnet
pub fn strk_token_address() -> ContractAddress {
    0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d.try_into().unwrap()
}

// LORDS token contract address on mainnet
pub fn lords_token_address() -> ContractAddress {
    0x0124aeb495b947201f5fac96fd1138e326ad86195b98df6dec9009158a533b49.try_into().unwrap()
}
