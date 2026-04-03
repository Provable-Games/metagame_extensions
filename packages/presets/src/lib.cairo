pub mod entry_fee;
pub mod entry_requirement;
pub mod prize;

#[cfg(test)]
pub mod tests {
    pub mod test_entry_validator;
    pub mod test_erc20_balance_validator_fork;
    pub mod test_governance_validator;
    pub mod test_governance_validator_fork;
    pub mod test_merkle_validator;
    pub mod test_opus_troves_validator_fork;
    pub mod test_snapshot_validator_fork;
    pub mod test_tournament_validator_fork;
    pub mod test_tournament_validator_integration;
    pub mod test_zkpassport_fork;
    pub mod test_zkpassport_validator;
}
