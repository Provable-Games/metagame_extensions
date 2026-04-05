[![Scarb](https://img.shields.io/badge/Scarb-2.15.1-blue)](https://github.com/software-mansion/scarb)
[![Starknet Foundry](https://img.shields.io/badge/snforge-0.56.0-purple)](https://foundry-rs.github.io/starknet-foundry/)
[![codecov](https://codecov.io/gh/Provable-Games/budokan_extensions/graph/badge.svg?token=K2VbKS8j8R)](https://codecov.io/gh/Provable-Games/budokan_extensions)

# Metagame Extensions

Modular extension contracts for metagame platforms on Starknet. Compatible with [Budokan](https://github.com/Provable-Games/budokan) and any platform implementing the same interfaces. Extensions define entry requirements, entry fees, prize distribution, and qualification criteria.

## Packages

| Package | Path | Description |
| ------- | ---- | ----------- |
| `metagame_extensions_interfaces` | `packages/interfaces/` | Pure traits and types for all extensions |
| `metagame_extensions_entry_requirement` | `packages/entry_requirement/` | `EntryRequirementExtensionComponent` for building entry validators |
| `metagame_extensions_entry_fee` | `packages/entry_fee/` | `EntryFeeExtensionComponent` for entry fee logic |
| `metagame_extensions_prize` | `packages/prize/` | `PrizeExtensionComponent` for prize distribution |
| `metagame_extensions_presets` | `packages/presets/` | Pre-built validator contracts |
| `metagame_extensions_test_common` | `packages/test_common/` | Shared test mocks and constants |

## Validators

| Validator | Description |
| --------- | ----------- |
| **ERC20 Balance** | Entries based on ERC20 token balance with min/max thresholds |
| **Governance** | Entries based on governance voting power and participation |
| **Merkle** | Entries based on merkle allowlist with off-chain proof API |
| **Snapshot** | Entries based on historical point-in-time snapshot data |
| **Opus Troves** | Entries based on Opus Protocol debt positions |
| **Tournament** | Entries based on prior tournament qualification |
| **ZK Passport** | Privacy-preserving entry via ZK proofs (Garaga Honk verifier) |

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
snforge test -p metagame_extensions_presets        # Run validator tests only
snforge test -p metagame_extensions_presets <name> # Run a specific test by filter
snforge test --workspace --coverage     # Run with code coverage
```

### Format

```bash
scarb fmt --workspace                   # Format Cairo files
scarb fmt --check --workspace           # Check formatting (used in CI)
```

## Deployment

Deployment scripts are in `scripts/`. Each validator has its own deploy script.

```bash
# 1. Configure environment
cp .env.example .env
# Edit .env with STARKNET_NETWORK, OWNER_ADDRESS, etc.

# 2. Deploy a validator
./scripts/deploy_erc20_balance_validator.sh
./scripts/deploy_governance_validator.sh
./scripts/deploy_opus_troves_validator.sh
./scripts/deploy_snapshot_validator.sh
./scripts/deploy_tournament_validator.sh
./scripts/deploy_zkpassport_validator.sh
./scripts/deploy_open_entry_validator.sh
```

Requires `starkli` and `scarb`. See [scripts/README.md](scripts/README.md) for detailed deployment instructions.
