# entry_validator_interfaces

Trait definitions and types for entry validators on Starknet. Compatible with tournament platforms like [Budokan](https://github.com/Provable-Games/budokan).

This package contains only pure traits and types with no component or contract logic, making it suitable as a lightweight dependency for any contract that needs to interact with entry validators.

## Modules

- `entry_requirement_extension` - `IEntryRequirementExtension` trait and `IENTRY_REQUIREMENT_EXTENSION_ID`
- `entry_requirement` - `EntryRequirement`, `QualificationProof`, `ExtensionConfig`
- `tournament` - `ITournament` dispatcher, `Tournament`, `Schedule`, `Phase`
- `distribution` - `Distribution` enum
- `prize` - `Prize`, `PrizeType`, `TokenTypeData`
- `registration` - `IRegistration` dispatcher

## Usage

```toml
[dependencies]
entry_validator_interfaces = { git = "https://github.com/Provable-Games/metagame-extensions", tag = "..." }
```
