# budokan_interfaces

Trait definitions and types for Budokan entry validators on Starknet.

This package contains only pure traits and types with no component or contract logic, making it suitable as a lightweight dependency for any contract that needs to interact with Budokan validators.

## Modules

- `entry_validator` - `IEntryValidator` trait and `IENTRY_VALIDATOR_ID`
- `entry_requirement` - `EntryRequirement`, `QualificationProof`, `ExtensionConfig`
- `budokan` - `IBudokan` dispatcher, `Tournament`, `Schedule`, `Phase`
- `distribution` - `Distribution` enum
- `prize` - `Prize`, `PrizeType`, `TokenTypeData`
- `registration` - `IRegistration` dispatcher

## Usage

```toml
[dependencies]
budokan_interfaces = { git = "https://github.com/Provable-Games/budokan-extensions", tag = "..." }
```
