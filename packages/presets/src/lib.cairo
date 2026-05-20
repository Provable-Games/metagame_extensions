pub mod entry_fee;
pub mod entry_requirement;
pub mod externals;
pub mod prize;

#[cfg(test)]
pub mod tests {
    pub mod test_entry_fee_presets;
    pub mod test_entry_validator;
    pub mod test_erc20_balance_validator;
    pub mod test_governance_validator;
    pub mod test_merkle_validator;
    pub mod test_opus_troves_validator;
    pub mod test_prize_presets;
    pub mod test_tournament_validator;
    pub mod test_zkpassport_validator;
}
