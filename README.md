# contracts

[![Solidity](https://img.shields.io/badge/Solidity-0.8.x-363636?logo=solidity)](https://soliditylang.org)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C)](https://getfoundry.sh)
[![Tests](https://img.shields.io/badge/Tests-34%20passing-brightgreen)](.)

Solidity smart contracts providing on-chain settlement, time-decaying reputation tracking, and inference provenance for the OBEY Agent Economy.

Part of the [Obey Agent Economy](https://github.com/lancekrogers/Obey-Agent-Economy) project.

> **TL;DR** — Three contracts cover the full lifecycle of agent work: `AgentSettlement` pays agents for completed tasks (single or batch), `ReputationDecay` scores agents with automatic linear decay so stale reputation fades, and `AgentINFT` mints ERC-7857 iNFTs that cryptographically anchor AI inference results to the 0G Chain DA layer. All three support Hedera HIP-1215 scheduled execution.

---

## Contracts

### AgentSettlement

Handles payment settlement from a coordinator to AI agents after task completion. Uses a `bytes32` task ID to prevent double-payment. Supports Hedera's HIP-1215 scheduled batch execution via the native Schedule Service at `0x167`.

**Key functions**

| Signature | Description |
|-----------|-------------|
| `settle(address agent, bytes32 taskId) external payable` | Pay an agent for a single completed task. Reverts on duplicate `taskId`. |
| `batchSettle(address[] agents, bytes32[] taskIds, uint256[] amounts) external payable` | Atomically settle payments to multiple agents in one transaction. |
| `scheduleBatchSettle(address[] agents, bytes32[] taskIds, uint256[] amounts, uint256 executeAt) external payable` | Queue a batch settlement for deferred on-chain execution via HIP-1215. |
| `transferOwnership(address newOwner) external` | Transfer coordinator ownership to a new address. |

**State**

- `mapping(bytes32 => bool) public settled` — tracks paid task IDs to prevent replay
- `uint256 public totalSettled` — cumulative wei settled across all tasks

**Events**

```solidity
event AgentPaid(address indexed agent, uint256 amount, bytes32 indexed taskId, uint256 timestamp);
```

**Custom errors:** `Unauthorized`, `ZeroAddress`, `ZeroAmount`, `AlreadySettled`, `InsufficientValue`, `TransferFailed`, `ArrayLengthMismatch`

---

### ReputationDecay

Tracks per-agent reputation scores with configurable linear time-decay. Scores decay continuously toward zero based on elapsed time since the last update. The coordinator calls `updateReputation` after each task; the decay is applied lazily on each read or write.

Default decay rate: **1 point per hour** (`1e18 / 3600` scaled by `1e18` for precision).

**Key functions**

| Signature | Description |
|-----------|-------------|
| `updateReputation(address agent, int256 delta) external` | Apply a positive (reward) or negative (penalty) delta to an agent's decayed score. Clamps to zero on underflow. |
| `getReputation(address agent) external view returns (uint256)` | Return the current decay-adjusted score without writing state. |
| `getRawReputation(address agent) external view returns (uint256 score, uint256 lastUpdated)` | Return the stored (pre-decay) score and the timestamp of the last update. |
| `setDecayRate(uint256 newRate) external` | Set the decay rate in points-per-second scaled by `1e18`. |
| `processDecay(address[] agents) external` | Force a decay pass and persist the result for a list of agents. |
| `scheduleDecay(address[] agents, uint256 executeAt) external` | Schedule a future `processDecay` call via HIP-1215. |
| `transferOwnership(address newOwner) external` | Transfer coordinator ownership to a new address. |

**Decay formula**

```
decayed_score = score - (elapsed_seconds * decayRatePerSecond / 1e18)
```
Clamped to zero. The timer resets on every `updateReputation` call.

**Events**

```solidity
event ReputationUpdated(address indexed agent, uint256 newScore, int256 delta, uint256 timestamp);
event DecayRateChanged(uint256 oldRate, uint256 newRate);
```

**Custom errors:** `Unauthorized`, `ZeroAddress`, `InvalidDecayRate`

---

### AgentINFT

ERC-721 token (ERC-7857 iNFT profile) for AI inference provenance on the 0G Chain. Each token stores encrypted inference metadata, a keccak256 result hash, and a DA-layer storage reference (`0g://...`). The ABI is designed to match the Go minter in `agent-inference/internal/zerog/inft/minter.go`.

**Key functions**

| Signature | Description |
|-----------|-------------|
| `mint(address to, string name, string description, bytes encryptedMeta, bytes32 resultHash, string storageRef) external returns (uint256)` | Mint a new iNFT with full token data. Returns the sequential token ID. |
| `updateEncryptedMetadata(uint256 tokenId, bytes encryptedMeta) external` | Update encrypted metadata for a token. Only callable by the current token owner. Automatically recomputes `metadataHash`. |
| `getTokenData(uint256 tokenId) external view returns (TokenData)` | Read the full `TokenData` struct for a token. |

**TokenData struct**

```solidity
struct TokenData {
    string  name;               // Human-readable job name
    string  description;        // Inference result description
    bytes   encryptedMetadata;  // Encrypted inference payload
    bytes32 metadataHash;       // keccak256 of encryptedMetadata
    string  daRef;              // 0G DA layer reference (e.g. "0g://abc123")
}
```

**Events**

```solidity
event Transfer(address indexed from, address indexed to, uint256 indexed tokenId); // ERC-721
event MetadataUpdated(uint256 indexed tokenId, bytes32 newHash);
```

---

### AgentIdentityRegistry

ERC-8004 agent identity registry for Base Sepolia. Agents register their public key and metadata on-chain for trustless identity verification. Matches the ABI expected by `agent-defi/internal/base/identity/register.go`.

**Key functions**

| Signature | Description |
|-----------|-------------|
| `register(bytes32 agentId, bytes pubKey, bytes metadata) external` | Register an agent identity. Reverts if already registered. |
| `getIdentity(bytes32 agentId) external view returns (uint8 status, bytes metadata, bytes signature)` | Get identity record for an agent. Status: 0=unregistered, 1=active, 2=revoked. |
| `revoke(bytes32 agentId) external` | Revoke an active agent identity. |

**Events**

```solidity
event AgentRegistered(bytes32 indexed agentId, address indexed owner);
event AgentRevoked(bytes32 indexed agentId);
```

---

### IHederaScheduleService (interface)

Interface for the Hedera Schedule Service system contract deployed at address `0x167`. Used by both `AgentSettlement` and `ReputationDecay` to enable HIP-1215 deferred execution.

```solidity
function scheduleNative(address to, uint256 value, bytes calldata data, uint256 expirationTime) external returns (address scheduleAddress);
function hasScheduleCapacity() external view returns (bool);
function signSchedule(address schedule) external;
```

---

## Project Structure

```
contracts/
├── src/
│   ├── AgentSettlement.sol            # Payment settlement with replay protection
│   ├── ReputationDecay.sol            # Time-decaying reputation scores
│   ├── AgentINFT.sol                  # ERC-7857 iNFT for inference provenance
│   ├── AgentIdentityRegistry.sol      # ERC-8004 agent identity registry
│   └── interfaces/
│       └── IHederaScheduleService.sol # HIP-1215 schedule service interface
├── test/
│   ├── AgentSettlement.t.sol          # 13 tests: settle, batch, HIP-1215, auth
│   ├── ReputationDecay.t.sol          # 14 tests: decay math, scheduling, edge cases
│   └── AgentINFT.t.sol               # 7 tests: mint, metadata update, ownership
├── script/
│   └── Deploy.s.sol                   # Forge broadcast script (Hedera, 0G, Base)
├── lib/
│   ├── forge-std/                     # Forge standard library
│   └── openzeppelin-contracts/        # OZ ERC-721, Ownable
├── foundry.toml                       # RPC endpoints: hedera, zerog
└── justfile                           # Build commands
```

---

## Deployment

The deploy script broadcasts all four contracts in a single run.

**0G Galileo testnet**

```bash
forge script script/Deploy.s.sol \
  --rpc-url zerog \
  --broadcast \
  --private-key $ZG_CHAIN_PRIVATE_KEY \
  --with-gas-price 3000000000 --priority-gas-price 3000000000
```

**Base Sepolia**

```bash
forge script script/Deploy.s.sol \
  --rpc-url https://sepolia.base.org \
  --broadcast \
  --private-key $DEFI_PRIVATE_KEY
```

**Hedera testnet**

```bash
forge script script/Deploy.s.sol \
  --rpc-url $HEDERA_RPC \
  --broadcast \
  --private-key $PRIVATE_KEY
```

RPC endpoints are preconfigured in `foundry.toml`:

| Network | RPC URL |
|---------|---------|
| Hedera testnet | `https://testnet.hashio.io/api` |
| 0G Galileo testnet | `https://evmrpc-testnet.0g.ai` |

### Deployed Addresses

**0G Galileo (Chain ID 16602)** — Wallet: `0x38CB2E2eeb45E6F70D267053DcE3815869a8C44d`

| Contract | Address |
|----------|---------|
| ReputationDecay | `0xbdCdBfd93C4341DfE3408900A830CBB0560a62C4` |
| AgentSettlement | `0x437c2bF7a00Da07983bc1eCaa872d9E2B27A3d40` |
| AgentINFT | `0x17F41075454cf268D0672dd24EFBeA29EF2Dc05b` |

**Base Sepolia (Chain ID 84532)** — Wallet: `0xc71d8a19422c649fe9bdcbf3ffa536326c82b58b`

| Contract | Address |
|----------|---------|
| AgentIdentityRegistry | `0x0C97820abBdD2562645DaE92D35eD581266CCe70` |
| AgentSettlement | `0xa5378FbDCD2799C549A559C1C7c1F91D7C983A44` |
| ReputationDecay | `0x54734cC3AF4Db984cD827f967BaF6C64DEAEd0B1` |
| AgentINFT | `0xfcA344515D72a05232DF168C1eA13Be22383cCB6` |

---

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) — `forge`, `cast`, `anvil`

Install dependencies after cloning:

```bash
forge install
```

---

## Development

```bash
just          # list available commands
just build    # forge build
just test     # forge test -v (34 tests)
just clean    # forge clean
```

Run tests with verbose output:

```bash
forge test -vvv
```

Run a single test file:

```bash
forge test --match-path test/AgentSettlement.t.sol -vv
```

---

## License

MIT

---

Part of the [ETHDenver 2026 Agent Economy](../README.md) submission.
