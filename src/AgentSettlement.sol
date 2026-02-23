// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IHederaScheduleService} from "./interfaces/IHederaScheduleService.sol";

/// @title AgentSettlement
/// @notice Handles settlement payments between the coordinator and AI agents.
/// The coordinator calls settle() after an agent completes a task, transferring
/// the agreed payment amount to the agent's on-chain address.
/// Supports HIP-1215 scheduled batch settlements via the Hedera Schedule Service.
contract AgentSettlement {
    // ── Errors ──────────────────────────────────────────────────────────

    error Unauthorized();
    error ZeroAddress();
    error ZeroAmount();
    error AlreadySettled();
    error InsufficientValue();
    error TransferFailed();
    error ArrayLengthMismatch();

    // ── Events ──────────────────────────────────────────────────────────

    /// @notice Emitted when an agent is paid for completing a task.
    event AgentPaid(
        address indexed agent,
        uint256 amount,
        bytes32 indexed taskId,
        uint256 timestamp
    );

    // ── State ───────────────────────────────────────────────────────────

    address public owner;
    mapping(bytes32 => bool) public settled;
    uint256 public totalSettled;

    // ── Constructor ─────────────────────────────────────────────────────

    constructor() {
        owner = msg.sender;
    }

    // ── Modifiers ───────────────────────────────────────────────────────

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    // ── Settlement ──────────────────────────────────────────────────────

    /// @notice Settle payment to an agent for a completed task.
    /// @param agent The agent's payment address.
    /// @param taskId Unique task identifier (prevents double settlement).
    function settle(address agent, bytes32 taskId) external payable onlyOwner {
        if (agent == address(0)) revert ZeroAddress();
        if (msg.value == 0) revert ZeroAmount();
        if (settled[taskId]) revert AlreadySettled();

        settled[taskId] = true;
        totalSettled += msg.value;

        (bool ok, ) = agent.call{value: msg.value}("");
        if (!ok) revert TransferFailed();

        emit AgentPaid(agent, msg.value, taskId, block.timestamp);
    }

    /// @notice Settle payments to multiple agents in a single transaction.
    /// @param agents Array of agent payment addresses.
    /// @param taskIds Array of unique task identifiers.
    /// @param amounts Array of payment amounts.
    function batchSettle(
        address[] calldata agents,
        bytes32[] calldata taskIds,
        uint256[] calldata amounts
    ) external payable onlyOwner {
        if (agents.length != taskIds.length || agents.length != amounts.length) {
            revert ArrayLengthMismatch();
        }

        uint256 totalRequired;
        for (uint256 i; i < amounts.length; ++i) {
            totalRequired += amounts[i];
        }
        if (msg.value < totalRequired) revert InsufficientValue();

        for (uint256 i; i < agents.length; ++i) {
            if (agents[i] == address(0)) revert ZeroAddress();
            if (amounts[i] == 0) revert ZeroAmount();
            if (settled[taskIds[i]]) revert AlreadySettled();

            settled[taskIds[i]] = true;
            totalSettled += amounts[i];

            (bool ok, ) = agents[i].call{value: amounts[i]}("");
            if (!ok) revert TransferFailed();

            emit AgentPaid(agents[i], amounts[i], taskIds[i], block.timestamp);
        }
    }

    // ── HIP-1215 Scheduling ──────────────────────────────────────────

    /// @notice Hedera Schedule Service system contract at address 0x167.
    IHederaScheduleService constant SCHEDULE = IHederaScheduleService(address(0x167));

    /// @notice Schedule a batch settlement for deferred execution via HIP-1215.
    /// @param agents Array of agent payment addresses.
    /// @param taskIds Array of unique task identifiers.
    /// @param amounts Array of payment amounts.
    /// @param executeAt Unix timestamp for scheduled execution.
    function scheduleBatchSettle(
        address[] calldata agents,
        bytes32[] calldata taskIds,
        uint256[] calldata amounts,
        uint256 executeAt
    ) external payable onlyOwner {
        require(SCHEDULE.hasScheduleCapacity(), "no schedule capacity");
        bytes memory data = abi.encodeWithSelector(
            this.batchSettle.selector, agents, taskIds, amounts
        );
        SCHEDULE.scheduleNative(address(this), msg.value, data, executeAt);
    }

    /// @notice Transfer ownership to a new address.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }
}
