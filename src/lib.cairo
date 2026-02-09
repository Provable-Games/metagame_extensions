pub mod deps;

pub mod presets {
    pub mod erc20_balance_validator;
    pub mod governance_validator;
    pub mod opus_troves_validator;
    pub mod snapshot_validator;
    pub mod tournament_validator;
    pub mod zkpassport_validator;
}

#[cfg(test)]
pub mod tests {
    pub mod constants;
    pub mod mocks {
        pub mod entry_validator_mock;
        pub mod open_entry_validator_mock;
    }
    pub mod test_entry_validator;
    pub mod test_erc20_balance_validator_budokan_fork;
    pub mod test_governance_validator;
    pub mod test_governance_validator_budokan_fork;
    pub mod test_opus_troves_validator_budokan_fork;
    // pub mod test_snapshot_validator_fork;
    pub mod test_snapshot_validator_budokan_fork;
    pub mod test_tournament_validator_budokan_fork;
    pub mod test_tournament_validator_integration;
    pub mod test_zkpassport_fork;
    pub mod test_zkpassport_validator;
}
