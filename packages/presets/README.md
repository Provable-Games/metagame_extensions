# entry_requirement_extensions

Pre-built entry validator contracts for tournament platforms like [Budokan](https://github.com/Provable-Games/budokan).

## Validators

| Validator | Description |
|-----------|-------------|
| `erc20_balance_validator` | Entries based on ERC-20 token balance |
| `governance_validator` | Entries based on voting power / participation |
| `merkle_validator` | Entries based on Merkle tree allowlists |
| `opus_troves_validator` | Entries based on Opus Protocol debt positions |
| `tournament_validator` | Entries based on prior tournament qualification |
| `zkpassport_validator` | Entries based on ZK passport proofs via Garaga |

## Testing

```bash
snforge test -p entry_requirement_extensions                        # All tests
snforge test -p entry_requirement_extensions test_governance        # Filter by name
snforge test -p entry_requirement_extensions --fork-name sepolia    # Fork tests only
```
