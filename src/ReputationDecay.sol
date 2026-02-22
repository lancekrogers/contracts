// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title ReputationDecay
/// @notice Tracks agent reputation with configurable linear time-decay.
/// Reputation decays linearly toward zero based on time elapsed since
/// the last update. The coordinator calls updateReputation() after each
/// completed task to increase or decrease an agent's score.
contract ReputationDecay {
    // ── Errors ──────────────────────────────────────────────────────────

    error Unauthorized();
    error ZeroAddress();
    error InvalidDecayRate();

    // ── Events ──────────────────────────────────────────────────────────

    /// @notice Emitted when an agent's reputation is updated.
    event ReputationUpdated(
        address indexed agent,
        uint256 newScore,
        int256 delta,
        uint256 timestamp
    );

    /// @notice Emitted when the decay rate is changed.
    event DecayRateChanged(uint256 oldRate, uint256 newRate);

    // ── State ───────────────────────────────────────────────────────────

    struct AgentReputation {
        uint256 score;
        uint256 lastUpdated;
    }

    address public owner;

    /// @notice Points decayed per second. Default: 1 point per hour (1/3600).
    /// Stored as points-per-second scaled by 1e18 for precision.
    uint256 public decayRatePerSecond;

    mapping(address => AgentReputation) public reputations;

    // ── Constants ───────────────────────────────────────────────────────

    uint256 constant PRECISION = 1e18;
    uint256 constant DEFAULT_DECAY_RATE = PRECISION / 3600; // ~1 point per hour

    // ── Constructor ─────────────────────────────────────────────────────

    constructor() {
        owner = msg.sender;
        decayRatePerSecond = DEFAULT_DECAY_RATE;
    }

    // ── Modifiers ───────────────────────────────────────────────────────

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    // ── Reputation ──────────────────────────────────────────────────────

    /// @notice Update an agent's reputation score by a delta (positive or negative).
    /// The current score is first decayed based on elapsed time, then the delta
    /// is applied. Negative deltas that would go below zero clamp to zero.
    /// @param agent The agent's address.
    /// @param delta The reputation change (positive = reward, negative = penalty).
    function updateReputation(address agent, int256 delta) external onlyOwner {
        if (agent == address(0)) revert ZeroAddress();

        AgentReputation storage rep = reputations[agent];

        // Apply time-decay to existing score.
        uint256 decayed = _decayedScore(rep.score, rep.lastUpdated);

        // Apply delta with underflow protection.
        uint256 newScore;
        if (delta >= 0) {
            // forge-lint: disable-next-line(unsafe-typecast)
            newScore = decayed + uint256(delta);
        } else {
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 penalty = uint256(-delta);
            newScore = penalty > decayed ? 0 : decayed - penalty;
        }

        rep.score = newScore;
        rep.lastUpdated = block.timestamp;

        emit ReputationUpdated(agent, newScore, delta, block.timestamp);
    }

    /// @notice Get the current (decayed) reputation score for an agent.
    /// @param agent The agent's address.
    /// @return score The current decayed reputation score.
    function getReputation(address agent) external view returns (uint256 score) {
        AgentReputation storage rep = reputations[agent];
        return _decayedScore(rep.score, rep.lastUpdated);
    }

    /// @notice Get the raw (non-decayed) reputation data for an agent.
    /// @param agent The agent's address.
    /// @return score The stored score (before decay).
    /// @return lastUpdated The timestamp of the last update.
    function getRawReputation(address agent) external view returns (uint256 score, uint256 lastUpdated) {
        AgentReputation storage rep = reputations[agent];
        return (rep.score, rep.lastUpdated);
    }

    // ── Configuration ───────────────────────────────────────────────────

    /// @notice Set the decay rate (points per second, scaled by 1e18).
    function setDecayRate(uint256 newRate) external onlyOwner {
        if (newRate == 0) revert InvalidDecayRate();
        emit DecayRateChanged(decayRatePerSecond, newRate);
        decayRatePerSecond = newRate;
    }

    /// @notice Transfer ownership to a new address.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }

    // ── Internal ────────────────────────────────────────────────────────

    /// @dev Calculate score after linear time-decay.
    function _decayedScore(uint256 score, uint256 lastUpdated) internal view returns (uint256) {
        if (score == 0 || lastUpdated == 0) return score;

        uint256 elapsed = block.timestamp - lastUpdated;
        if (elapsed == 0) return score;

        // decay = elapsed * decayRatePerSecond / PRECISION
        uint256 decay = (elapsed * decayRatePerSecond) / PRECISION;
        return decay >= score ? 0 : score - decay;
    }
}
