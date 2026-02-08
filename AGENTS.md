## Project Overview

**budokan-extensions** is a Cairo smart contract library providing modular **entry validators** for the [Budokan](https://github.com/Provable-Games/budokan) tournament platform on Starknet. Each validator implements qualification criteria that determine who can enter tournaments and how many entries they receive.

## Build & Test Commands

```bash
scarb build                    # Compile contracts
scarb run test                 # Run all tests (alias for snforge test)
snforge test                   # Run all tests directly
snforge test <test_name>       # Run a specific test by name filter
snforge test --coverage        # Run tests with code coverage (used in CI)
scarb fmt                      # Format all Cairo files
scarb fmt --check              # Check formatting without modifying (used in CI)
```

Fork testing (against live Starknet state):

```bash
snforge test --fork-name sepolia    # Test against Sepolia
snforge test --fork-name mainnet    # Test against Mainnet
```

## Toolchain Versions

Pinned in `.tool-versions` — currently Scarb 2.13.1, Starknet Foundry 0.53.0, Rust 1.89.0.

## Architecture

### EntryValidator Trait

All validators implement the `EntryValidator` trait from `budokan_entry_requirement`. The core lifecycle:

1. **`add_config(tournament_id, entry_limit, config)`** — Called by Budokan when a tournament registers this validator. Asserts caller is Budokan. Deserializes `config: Span<felt252>` into validator-specific settings stored in per-tournament Maps.
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

    // 3. Constructor: calls self.entry_validator.initializer(budokan_address, registration_only)
    //    registration_only=true means banning is supported

    // 4. impl EntryValidator<ContractState> — the 6 trait methods above
}
```

### Validators (in `src/examples/`)

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

- **Unit tests**: `test_entry_validator.cairo` — mock-based basic validation
- **Fork tests** (`*_budokan_fork`): Run against live Sepolia/Mainnet Budokan contracts
- **Integration tests** (`*_integration`): Multi-contract workflows with locally deployed contracts
- **Mocks** (`src/tests/mocks/`): `entry_validator_mock`, `open_entry_validator_mock`, `erc721_mock`
- **Constants** (`src/tests/constants.cairo`): Mainnet/Sepolia addresses for Budokan, tokens, governance

### Dependencies

- **budokan_interfaces** / **budokan_entry_requirement**: Core Budokan traits (from `Provable-Games/budokan`, branch `main`)
- **OpenZeppelin Cairo v3.0.0-alpha.3**: Token, governance, SRC5, access control
- **opus** (v1.1.0): Opus Protocol lending contracts (for troves validator)
- **wadray** (v0.3.0): Fixed-point WAD/RAY math
- **game_components_minigame**: Game components from Provable-Games

## CI

The `test-contracts` workflow runs `scarb fmt --check` then `snforge test --coverage` on every PR and push to main. Code coverage is uploaded to Codecov with a 90% patch target.

## Adding a New Validator

1. Create `src/examples/my_validator.cairo` following the contract structure pattern above
2. Add the module to `src/lib.cairo` under `pub mod examples`
3. Create tests (at minimum a fork test) and register in `src/lib.cairo` under `pub mod tests`
4. Add a deployment script in `scripts/`
