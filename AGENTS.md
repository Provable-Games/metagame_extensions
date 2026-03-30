## Role

You are a senior software engineer specializing in the Cairo programming language, Starknet smart contracts, and Starknet Foundry testing framework.

## Project Overview

**metagame-extensions** is a Cairo smart contract library providing modular **entry validators** for tournament platforms on Starknet, such as [Budokan](https://github.com/Provable-Games/budokan). Each validator implements qualification criteria that determine who can enter tournaments and how many entries they receive.

The repo is structured as a Scarb workspace with four packages:

| Package                      | Path                        | Purpose                                                      |
| ---------------------------- | --------------------------- | ------------------------------------------------------------ |
| `entry_validator_interfaces` | `packages/interfaces/`      | Pure traits and types (`IEntryRequirementExtension`, `ITournament`, etc.) |
| `entry_validator_component`  | `packages/entry_validator/` | `EntryValidatorComponent` SDK for building validators        |
| `entry_requirement_extensions`           | `packages/presets/`      | All 6 pre-built validator contracts + tests                  |
| `entry_validator_test_common`| `packages/test_common/`     | Shared mocks and test constants                              |

## Build & Test Commands

```bash
scarb build                                    # Compile all packages
snforge test --workspace                       # Run all tests
snforge test -p entry_requirement_extensions               # Run validator tests only
snforge test -p entry_requirement_extensions <filter>      # Run a specific test by name filter
snforge test --workspace --coverage            # Run tests with code coverage (used in CI)
scarb fmt --workspace                          # Format all Cairo files
scarb fmt --check --workspace                  # Check formatting without modifying (used in CI)
```

Fork testing (against live Starknet state):

```bash
snforge test -p entry_requirement_extensions --fork-name sepolia    # Test against Sepolia
snforge test -p entry_requirement_extensions --fork-name mainnet    # Test against Mainnet
```

## Toolchain Versions

Pinned in `.tool-versions` — currently Scarb 2.15.1, Starknet Foundry 0.56.0, Rust 1.89.0.

## Architecture

### Package Dependency Graph

```
starknet (external)
    |
entry_validator_interfaces ─── depends on: starknet only
    |
entry_validator_component ─── depends on: entry_validator_interfaces, openzeppelin_introspection
    |
entry_requirement_extensions ─── depends on: entry_validator_interfaces, entry_validator_component,
    |                              openzeppelin_introspection, openzeppelin_interfaces
    |
entry_validator_test_common ─── depends on: entry_validator_interfaces, entry_validator_component,
                                             openzeppelin_introspection, openzeppelin_interfaces, snforge_std
```

### EntryValidator Trait

All validators implement the `EntryValidator` trait from `entry_validator_component`. The core lifecycle:

1. **`add_config(tournament_id, entry_limit, config)`** — Called by the owner (e.g. Budokan) when a tournament registers this validator. Asserts caller is the owner. Deserializes `config: Span<felt252>` into validator-specific settings stored in per-tournament Maps.
2. **`validate_entry(tournament_id, player_address, qualification)`** — Returns bool. Checks if player meets entry criteria.
3. **`entries_left(tournament_id, player_address, qualification)`** — Returns `Option<u8>` (None = unlimited).
4. **`on_entry_added(tournament_id, game_token_id, player_address, qualification)`** — Called after entry confirmed; tracks state (e.g., increment entry count).
5. **`should_ban_entry(tournament_id, game_token_id, current_owner, qualification)`** — Ongoing eligibility check; returns true to revoke entry.
6. **`on_entry_removed(tournament_id, game_token_id, player_address, qualification)`** — Cleanup when entry is revoked.

### Contract Structure Pattern

Every validator follows this pattern:

```cairo
#[starknet::contract]
pub mod MyValidator {
    // 1. Components: EntryValidatorComponent + SRC5Component (always both)
    component!(path: EntryValidatorComponent, storage: entry_validator, event: EntryValidatorEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    // 2. Storage: substorage for components + per-tournament Maps keyed by u64 tournament_id
    #[storage]
    struct Storage {
        #[substorage(v0)] entry_validator: ...,
        #[substorage(v0)] src5: ...,
        tournament_<setting>: Map<u64, T>,
        tournament_entries_per_address: Map<(u64, ContractAddress), u8>,
    }

    // 3. Constructor: calls self.entry_validator.initializer(owner_address, registration_only)
    //    registration_only=true means banning is supported

    // 4. impl EntryValidator<ContractState> — the 6 trait methods above
}
```

### Validators (in `packages/presets/src/`)

| Validator                 | Config Parameters                                                                          | Banning | Key Concept                                                        |
| ------------------------- | ------------------------------------------------------------------------------------------ | ------- | ------------------------------------------------------------------ |
| `erc20_balance_validator` | token_address, min/max_threshold, value_per_entry, max_entries                             | Yes     | Entries scale with token balance                                   |
| `governance_validator`    | governor, token, threshold, proposal_id, check_voted, votes_threshold, votes_per_entry     | Yes     | Voting power / participation                                       |
| `snapshot_validator`      | snapshot_id                                                                                | No      | Historical point-in-time data                                      |
| `opus_troves_validator`   | asset_addresses, debt_threshold, value_per_entry, max_entries                              | Yes     | Opus Protocol debt positions, WAD math                             |
| `tournament_validator`    | qualifier_type, qualifying_mode, top_positions, tournament_ids                             | Partial | Prior tournament qualification (PER_TOKEN / ALL modes)             |
| `zkpassport_validator`    | verifier_address, service_scope, subscope, param_commitment, max_proof_age, nullifier_type | No      | ZK proof via Garaga Honk verifier, sybil prevention via nullifiers |

### Storage Conventions

- Tournament-scoped: `Map<u64, T>` keyed by `tournament_id`
- Player-scoped: `Map<(u64, ContractAddress), T>` keyed by `(tournament_id, player)`
- Token-scoped: `Map<(u64, u256), T>` keyed by `(tournament_id, token_id)`
- Config is packed into `Span<felt252>` and deserialized in `add_config`

### Test Organization

- **Unit tests**: `packages/presets/src/tests/test_entry_validator.cairo` — mock-based basic validation
- **Fork tests** (`*_fork`): Run against live Sepolia/Mainnet contracts (e.g. Budokan)
- **Integration tests** (`*_integration`): Multi-contract workflows with locally deployed contracts
- **Mocks** (`packages/test_common/src/mocks/`): `entry_validator_mock`, `open_entry_validator_mock`
- **Constants** (`packages/test_common/src/constants.cairo`): Mainnet/Sepolia addresses for tournament platforms, tokens, governance
- **Examples** (`examples/`): Uncompiled reference/WIP validators (not part of any package)

### Dependencies

- **openzeppelin_introspection** (3.0.0): SRC5 interface detection
- **openzeppelin_interfaces** (2.1.0): ERC20, ERC721, Governor, Votes interfaces
- **snforge_std** (0.56.0): Starknet Foundry test framework (dev-dependency)

External protocol type stubs are vendored in `packages/presets/src/externals/`:

- `wadray.cairo` — Fixed-point WAD/RAY math (from Opus)
- `opus.cairo` — Opus Protocol types (AssetBalance)
- `game_components.cairo` — IMinigame interface (from Provable-Games)

## CI

The `test-contracts` workflow runs `scarb fmt --check --workspace` then `snforge test --workspace --coverage` on every PR and push to main. Code coverage is uploaded to Codecov with a 90% patch target.

## Adding a New Validator

1. Create `packages/presets/src/my_validator.cairo` following the contract structure pattern above
2. Add the module to `packages/presets/src/lib.cairo`
3. Create tests in `packages/presets/src/tests/` and register in `lib.cairo` under `#[cfg(test)] pub mod tests`
4. Add a deployment script in `scripts/`
