# contracts

Solidity contracts for agent settlement and reputation tracking.

Part of the [ETHDenver 2026 Agent Economy](../README.md) submission.

> **Status:** Scaffolded but not yet implemented. Optional Track 2 submission.

## Planned Contracts

| Contract | Purpose |
|----------|---------|
| `AgentSettlement.sol` | Cross-agent payment settlement on-chain |
| `ReputationDecay.sol` | Time-decaying reputation scores for agents |

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)

## Development

```bash
just build    # forge build
just test     # forge test
just clean    # forge clean
```

## License

Apache-2.0
