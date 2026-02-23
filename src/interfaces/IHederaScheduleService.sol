// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title IHederaScheduleService
/// @notice Interface for the Hedera Schedule Service system contract at address 0x167.
/// Enables Solidity contracts to create scheduled transactions via HIP-1215.
interface IHederaScheduleService {
    /// @notice Schedule a native transaction for deferred execution.
    /// @param to Target contract or account address.
    /// @param value HBAR value to send with the scheduled call.
    /// @param data Encoded function call data.
    /// @param expirationTime Unix timestamp when the schedule expires.
    /// @return scheduleAddress The address of the created schedule entity.
    function scheduleNative(
        address to,
        uint256 value,
        bytes calldata data,
        uint256 expirationTime
    ) external returns (address scheduleAddress);

    /// @notice Check whether the network has capacity for new scheduled transactions.
    /// @return True if scheduling is available.
    function hasScheduleCapacity() external view returns (bool);

    /// @notice Add a signature to an existing scheduled transaction.
    /// @param schedule The schedule entity address to sign.
    function signSchedule(address schedule) external;
}
