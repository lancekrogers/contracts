// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title AgentIdentityRegistry
/// @notice ERC-8004 agent identity registry for Base Sepolia.
/// Agents register their public key and metadata on-chain.
/// Matches the ABI expected by agent-defi/internal/base/identity/register.go.
contract AgentIdentityRegistry {
    struct IdentityRecord {
        uint8 status; // 0=unregistered, 1=active, 2=revoked
        bytes pubKey;
        bytes metadata;
    }

    mapping(bytes32 => IdentityRecord) private _identities;

    event AgentRegistered(bytes32 indexed agentId, address indexed owner);
    event AgentRevoked(bytes32 indexed agentId);

    /// @notice Register an agent identity.
    /// @dev ABI: register(bytes32 agentId, bytes pubKey, bytes metadata)
    function register(bytes32 agentId, bytes calldata pubKey, bytes calldata metadata) external {
        require(_identities[agentId].status == 0, "already registered");
        _identities[agentId] = IdentityRecord(1, pubKey, metadata);
        emit AgentRegistered(agentId, msg.sender);
    }

    /// @notice Get identity record for an agent.
    /// @dev ABI: getIdentity(bytes32) returns (uint8 status, bytes metadata, bytes signature)
    function getIdentity(bytes32 agentId) external view returns (uint8 status, bytes memory metadata, bytes memory signature) {
        IdentityRecord storage record = _identities[agentId];
        return (record.status, record.metadata, record.pubKey);
    }

    /// @notice Revoke an agent identity. Only callable if already registered.
    function revoke(bytes32 agentId) external {
        require(_identities[agentId].status == 1, "not active");
        _identities[agentId].status = 2;
        emit AgentRevoked(agentId);
    }
}
