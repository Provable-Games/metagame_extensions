# budokan_entry_validator

SDK for building Budokan entry validators. Provides `EntryValidatorComponent` which handles SRC5 registration, Budokan-only access control, and the bridge between the `IEntryValidator` interface and your validator's custom logic.

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
budokan_entry_validator = { git = "https://github.com/Provable-Games/budokan-extensions", tag = "..." }
budokan_interfaces = { git = "https://github.com/Provable-Games/budokan-extensions", tag = "..." }
```
