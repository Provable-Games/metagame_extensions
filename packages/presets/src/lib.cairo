pub mod entry_fee;
pub mod entry_requirement;
pub mod prize;

#[cfg(test)]
pub mod tests {
    pub mod test_entry_validator;
    pub mod test_governance_validator;
    pub mod test_merkle_validator;
    pub mod test_zkpassport_validator;
}
