pub mod erc20_balance_validator;
pub mod governance_validator;
pub mod opus_troves_validator;
pub mod snapshot_validator;
pub mod tournament_validator;
pub mod zkpassport_validator;

pub mod externals {
    pub mod game_components;
    pub mod opus;
    pub mod wadray;
}

#[cfg(test)]
pub mod tests {
    pub mod test_entry_validator;
    pub mod test_erc20_balance_validator_fork;
    pub mod test_governance_validator;
    pub mod test_governance_validator_fork;
    pub mod test_opus_troves_validator_fork;
    pub mod test_snapshot_validator_fork;
    pub mod test_tournament_validator_fork;
    pub mod test_tournament_validator_integration;
    pub mod test_zkpassport_fork;
    pub mod test_zkpassport_validator;
}
