# entry_validator_component

SDK for building entry validators. Provides `EntryValidatorComponent` which handles SRC5 registration, owner-only access control, and the bridge between the `IEntryRequirementExtension` interface and your validator's custom logic. Compatible with tournament platforms like [Budokan](https://github.com/Provable-Games/budokan).

## Usage

Implement the `EntryValidator` trait from the component, then embed the component in your contract:

```cairo
#[starknet::contract]
mod MyValidator {
    component!(path: EntryValidatorComponent, storage: entry_validator, event: EntryValidatorEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    // ... implement EntryValidator<ContractState> ...
}
```

## Dependencies

```toml
[dependencies]
entry_validator_component = { git = "https://github.com/Provable-Games/budokan-extensions", tag = "..." }
entry_validator_interfaces = { git = "https://github.com/Provable-Games/budokan-extensions", tag = "..." }
```
