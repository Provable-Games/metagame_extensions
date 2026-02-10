# budokan_validators

Pre-built entry validator contracts for the Budokan tournament platform.

## Validators

| Validator | Description |
|-----------|-------------|
| `erc20_balance_validator` | Entries based on ERC-20 token balance |
| `governance_validator` | Entries based on voting power / participation |
| `opus_troves_validator` | Entries based on Opus Protocol debt positions |
| `snapshot_validator` | Entries based on historical point-in-time data |
| `tournament_validator` | Entries based on prior tournament qualification |
| `zkpassport_validator` | Entries based on ZK passport proofs via Garaga |

## Testing

```bash
snforge test -p budokan_validators                        # All tests
snforge test -p budokan_validators test_governance        # Filter by name
snforge test -p budokan_validators --fork-name sepolia    # Fork tests only
```
