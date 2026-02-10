[![Scarb](https://img.shields.io/badge/Scarb-2.15.1-blue)](https://github.com/software-mansion/scarb)
[![Starknet Foundry](https://img.shields.io/badge/snforge-0.56.0-purple)](https://foundry-rs.github.io/starknet-foundry/)
[![codecov](https://codecov.io/gh/Provable-Games/budokan_extensions/graph/badge.svg?token=K2VbKS8j8R)](https://codecov.io/gh/Provable-Games/budokan_extensions)

# Budokan Extensions

Modular entry validators for the [Budokan](https://github.com/Provable-Games/budokan) tournament platform on Starknet. Each validator defines qualification criteria that determine who can enter a tournament and how many entries they receive.

## Packages

| Package | Description |
| ------- | ----------- |
| [`budokan_interfaces`](packages/interfaces/) | Pure traits and types for entry validators |
| [`budokan_entry_validator`](packages/entry_validator/) | `EntryValidatorComponent` SDK for building validators |
| [`budokan_validators`](packages/validators/) | Pre-built validator contracts |
| [`budokan_test_common`](packages/test_common/) | Shared test mocks and constants |

## Validators

| Validator         | Description                                                   |
| ----------------- | ------------------------------------------------------------- |
| **ERC20 Balance** | Entries based on ERC20 token balance with min/max thresholds  |
| **Governance**    | Entries based on governance voting power and participation    |
| **Snapshot**      | Entries based on historical point-in-time snapshot data       |
| **Opus Troves**   | Entries based on Opus Protocol debt positions                 |
| **Tournament**    | Entries based on prior tournament qualification               |
| **ZK Passport**   | Privacy-preserving entry via ZK proofs (Garaga Honk verifier) |

## Getting Started

### Prerequisites

Toolchain versions are pinned in `.tool-versions`:

- [Scarb](https://docs.swmansion.com/scarb/) 2.15.1
- [Starknet Foundry](https://foundry-rs.github.io/starknet-foundry/) 0.56.0

### Build

```bash
scarb build                             # Build all packages
```

### Test

```bash
snforge test --workspace                # Run all tests
snforge test -p budokan_validators      # Run validator tests only
snforge test -p budokan_validators <name> # Run a specific test by filter
snforge test --workspace --coverage     # Run with code coverage
```

### Format

```bash
scarb fmt --workspace                   # Format Cairo files
scarb fmt --check --workspace           # Check formatting (used in CI)
```

## Deployed Contracts

| Validator | Mainnet | Sepolia |
| --------- | ------- | ------- |
| **ZK Passport** | [`0x01a2...2f4c`](https://voyager.online/contract/0x01a25f04d151c1295ba3223f7e63b89ec89762fe29d68c5f1896f86cadf62f4c) | [`0x046a...0c7f`](https://sepolia.voyager.online/contract/0x046af2c4fe14ddf0f6a3bf91a3981e71c1b150e85701d387a05a201b1c530c7f) |

## Deployment

Deployment scripts are in `scripts/`. Each validator has its own deploy script.

```bash
# 1. Configure environment
cp .env.example .env
# Edit .env with STARKNET_NETWORK, BUDOKAN_ADDRESS, etc.

# 2. Deploy a validator
./scripts/deploy_snapshot_validator.sh
./scripts/deploy_erc20_balance_validator.sh
./scripts/deploy_tournament_validator.sh
./scripts/deploy_opus_troves_validator.sh
./scripts/deploy_open_entry_validator.sh
```

Requires `starkli` and `scarb`. See [scripts/README.md](scripts/README.md) for detailed deployment instructions.
