# contracts

Solidity contracts for agent settlement and reputation tracking.

Part of the [ETHDenver 2026 Agent Economy](../README.md) submission.

**Status:** Implemented. All contracts compile and pass Forge tests (34 tests).

## Contracts

| Contract | Purpose |
|----------|---------|
| `AgentSettlement.sol` | Cross-agent payment settlement on-chain (settle, batchSettle, ownership, events) |
| `ReputationDecay.sol` | Time-decaying reputation scores for agents (updateReputation, getReputation) |
| `AgentINFT.sol` | ERC-7857 iNFT for agent inference provenance on 0G Chain (mint, updateEncryptedMetadata, getTokenData) |

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)

## Development

```bash
just build    # forge build
just test     # forge test
just clean    # forge clean
```

## License

MIT
