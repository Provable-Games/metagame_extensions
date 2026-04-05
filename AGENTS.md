## Role

You are a senior software engineer specializing in the Cairo programming language, Starknet smart contracts, and Starknet Foundry testing framework.

## Project Overview

**metagame-extensions** is a Cairo smart contract library providing modular **extensions** for metagame platforms on Starknet, such as [Budokan](https://github.com/Provable-Games/budokan). Extensions implement entry requirements, entry fees, and prize distribution for tournament contexts.

The repo is structured as a Scarb workspace with six packages:

| Package                              | Path                        | Purpose                                                                  |
| ------------------------------------ | --------------------------- | ------------------------------------------------------------------------ |
| `metagame_extensions_interfaces`     | `packages/interfaces/`      | Pure traits and types (`IEntryRequirementExtension`, `IEntryFeeExtension`, `IPrizeExtension`) |
| `metagame_extensions_entry_requirement` | `packages/entry_requirement/` | `EntryRequirementExtensionComponent` SDK for building entry validators |
| `metagame_extensions_entry_fee`      | `packages/entry_fee/`       | `EntryFeeExtensionComponent` SDK for entry fee logic                     |
| `metagame_extensions_prize`          | `packages/prize/`           | `PrizeExtensionComponent` SDK for prize distribution                     |
| `metagame_extensions_presets`        | `packages/presets/`         | Pre-built validator contracts + tests                                    |
| `metagame_extensions_test_common`    | `packages/test_common/`     | Shared mocks and test constants                                          |

## Build & Test Commands

```bash
scarb build                                    # Compile all packages
snforge test --workspace                       # Run all tests
snforge test -p metagame_extensions_presets               # Run validator tests only
snforge test -p metagame_extensions_presets <filter>      # Run a specific test by name filter
snforge test --workspace --coverage            # Run tests with code coverage (used in CI)
scarb fmt --workspace                          # Format all Cairo files
scarb fmt --check --workspace                  # Check formatting without modifying (used in CI)
```

Fork testing (against live Starknet state):

```bash
snforge test -p metagame_extensions_presets --fork-name sepolia    # Test against Sepolia
snforge test -p metagame_extensions_presets --fork-name mainnet    # Test against Mainnet
```

## Toolchain Versions

Pinned in `.tool-versions` — currently Scarb 2.15.1, Starknet Foundry 0.56.0, Rust 1.89.0.

## Architecture

### Package Dependency Graph

```
starknet (external)
    |
metagame_extensions_interfaces ─── depends on: starknet only
    |
metagame_extensions_entry_requirement ─── depends on: interfaces, openzeppelin_introspection
metagame_extensions_entry_fee ─────────── depends on: interfaces, openzeppelin_introspection
metagame_extensions_prize ─────────────── depends on: interfaces, openzeppelin_introspection
    |
metagame_extensions_presets ─── depends on: interfaces, entry_requirement, entry_fee, prize,
    |                              openzeppelin_introspection, openzeppelin_interfaces
    |
metagame_extensions_test_common ─── depends on: interfaces, entry_requirement,
                                                 openzeppelin_introspection, snforge_std
```

### Extension Interfaces

Three extension interfaces are defined in `packages/interfaces/`:

**IEntryRequirementExtension** — Entry validation:
1. **`context_owner(context_id)`** — Returns the owner contract address for a context
2. **`registration_only()`** — Whether this validator only validates during registration
3. **`valid_entry(context_id, player_address, qualification)`** — Returns bool
4. **`should_ban(context_id, game_token_id, current_owner, qualification)`** — Ongoing eligibility
5. **`entries_left(context_id, player_address, qualification)`** — Returns `Option<u32>` (None = unlimited)
6. **`add_config(context_id, entry_limit, config)`** — Called by owner during setup (`entry_limit: u32`)
7. **`add_entry(context_id, game_token_id, player_address, qualification)`** — Track entry
8. **`remove_entry(context_id, game_token_id, player_address, qualification)`** — Cleanup on ban

**IEntryFeeExtension** — Entry fee management:
1. **`context_owner(context_id)`** — Owner for a context
2. **`set_entry_fee_config(context_id, config)`** — Configure fees
3. **`pay_entry_fee(context_id, pay_params)`** — Process payment
4. **`claim_entry_fee(context_id, claim_params)`** — Claim collected fees

**IPrizeExtension** — Prize distribution:
1. **`context_owner(context_id)`** — Owner for a context
2. **`add_prize(context_id, prize_id, config)`** — Configure a prize
3. **`claim_prize(context_id, claim_params)`** — Claim a prize

### Contract Structure Pattern

Every validator follows this pattern:

```cairo
#[starknet::contract]
pub mod MyValidator {
    // 1. Components: EntryRequirementExtensionComponent + SRC5Component (always both)
    component!(path: EntryRequirementExtensionComponent, storage: entry_requirement, event: EntryRequirementEvent);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);

    // 2. Storage: substorage for components + per-context Maps keyed by u64 context_id
    #[storage]
    struct Storage {
        #[substorage(v0)] entry_requirement: ...,
        #[substorage(v0)] src5: ...,
        context_<setting>: Map<u64, T>,
        context_entries: Map<(u64, ContractAddress), u32>,
    }

    // 3. Constructor: calls self.entry_requirement.initializer(owner_address, registration_only)
    //    registration_only=true means banning is supported

    // 4. impl IEntryRequirementExtension<ContractState> — the 8 trait methods above
}
```

### Validators (in `packages/presets/src/`)

| Validator                 | Config Parameters                                                                          | Banning | Key Concept                                                        |
| ------------------------- | ------------------------------------------------------------------------------------------ | ------- | ------------------------------------------------------------------ |
| `erc20_balance_validator` | token_address, min/max_threshold, value_per_entry, max_entries                             | Yes     | Entries scale with token balance                                   |
| `governance_validator`    | governor, token, threshold, proposal_id, check_voted, votes_threshold, votes_per_entry     | Yes     | Voting power / participation                                       |
| `merkle_validator`        | merkle root (on-chain), entries via off-chain API                                          | No      | Merkle allowlist with proof lookup API                             |
| `snapshot_validator`      | snapshot_id                                                                                | No      | Historical point-in-time data                                      |
| `opus_troves_validator`   | asset_addresses, debt_threshold, value_per_entry, max_entries                              | Yes     | Opus Protocol debt positions, WAD math                             |
| `tournament_validator`    | qualifier_type, qualifying_mode, top_positions, tournament_ids                             | Partial | Prior tournament qualification (PER_TOKEN / ALL modes)             |
| `zkpassport_validator`    | verifier_address, service_scope, subscope, param_commitment, max_proof_age, nullifier_type | No      | ZK proof via Garaga Honk verifier, sybil prevention via nullifiers |

### Storage Conventions

- Context-scoped: `Map<u64, T>` keyed by `context_id`
- Player-scoped: `Map<(u64, ContractAddress), T>` keyed by `(context_id, player)`
- Token-scoped: `Map<(u64, u256), T>` keyed by `(context_id, token_id)`
- Config is packed into `Span<felt252>` and deserialized in `add_config`

### Test Organization

- **Unit tests**: `packages/presets/src/tests/` — mock-based basic validation
- **Fork tests** (`*_fork`): Run against live Sepolia/Mainnet contracts
- **Integration tests** (`*_integration`): Multi-contract workflows with locally deployed contracts
- **Mocks** (`packages/test_common/src/mocks/`): `entry_validator_mock`, `open_entry_validator_mock`
- **Constants** (`packages/test_common/src/constants.cairo`): Mainnet/Sepolia addresses for tournament platforms, tokens, governance
- **Examples** (`examples/`): Uncompiled reference/WIP validators (not part of any package)

## Computing SRC5 Interface IDs

Use `src5_rs parse` to compute interface IDs. The tool is pre-installed at `~/.cargo/bin/src5_rs`.

**Critical:** `src5_rs` v2.0.0 cannot parse modern Cairo `<TState>` generics or `self` parameters. You must create a temporary stripped-down file:

1. Remove `<TState>` generic from the trait
2. Remove `self: @TState` / `ref self: TState` from all function signatures
3. Include struct definitions inline (the tool doesn't resolve imports)
4. Remove `pub` modifiers

Example — to compute the ID for `IEntryRequirementExtension`:

Create `/tmp/src5_input.cairo`:

```cairo
#[starknet::interface]
trait IEntryRequirementExtension {
    fn context_owner(context_id: u64) -> ContractAddress;
    fn registration_only() -> bool;
    fn valid_entry(
        context_id: u64,
        player_address: ContractAddress,
        qualification: Span<felt252>,
    ) -> bool;
    fn should_ban(
        context_id: u64,
        game_token_id: felt252,
        current_owner: ContractAddress,
        qualification: Span<felt252>,
    ) -> bool;
    fn entries_left(
        context_id: u64,
        player_address: ContractAddress,
        qualification: Span<felt252>,
    ) -> Option<u32>;
    fn add_config(context_id: u64, entry_limit: u32, config: Span<felt252>);
    fn add_entry(
        context_id: u64,
        game_token_id: felt252,
        player_address: ContractAddress,
        qualification: Span<felt252>,
    );
    fn remove_entry(
        context_id: u64,
        game_token_id: felt252,
        player_address: ContractAddress,
        qualification: Span<felt252>,
    );
}
```

Then run:

```bash
src5_rs parse /tmp/src5_input.cairo
```

The tool outputs the extended function selectors and the final XOR'd interface ID.

**Important notes:**
- `ByteArray` expands to `(Array<bytes31>,felt252,usize)` — note `usize`, not `u32`
- `bool` expands to `E((),())` (an enum)
- `Span<T>` expands to `(@Array<T>)`
- `Option<T>` expands to `E(T,())` (an enum)
- For multi-function interfaces, the ID is the XOR of all extended function selectors
- For single-function interfaces, the ID equals the single extended function selector
- Always update the comment above the constant to document the derivation

## Dependencies

- **openzeppelin_introspection** (3.0.0): SRC5 interface detection
- **openzeppelin_interfaces** (3.0.0): ERC20, ERC721, Governor, Votes interfaces
- **openzeppelin_merkle_tree** (3.0.0): Merkle proof verification
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
