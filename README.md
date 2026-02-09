[![Scarb](https://img.shields.io/badge/Scarb-2.15.1-blue)](https://github.com/software-mansion/scarb)
[![Starknet Foundry](https://img.shields.io/badge/snforge-0.56.0-purple)](https://foundry-rs.github.io/starknet-foundry/)
[![codecov](https://codecov.io/gh/Provable-Games/budokan_extensions/graph/badge.svg?token=K2VbKS8j8R)](https://codecov.io/gh/Provable-Games/budokan_extensions)

# Budokan Extensions

Modular entry validators for the [Budokan](https://github.com/Provable-Games/budokan) tournament platform on Starknet. Each validator defines qualification criteria that determine who can enter a tournament and how many entries they receive.

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
scarb build
```

### Test

```bash
scarb run test                          # Run all tests
snforge test <test_name>                # Run a specific test
snforge test --coverage                 # Run with code coverage
snforge test --fork-name sepolia        # Run against live Sepolia state
snforge test --fork-name mainnet        # Run against live Mainnet state
```

### Format

```bash
scarb fmt                               # Format Cairo files
scarb fmt --check                       # Check formatting (used in CI)
```

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
