// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title ErrorsLib
/// @author @ohMySol
/// @notice Library of errors for the project contracts
library ErrorsLib {
    /// @notice Thrown when the fee BPS is too high
    error InvalidFeeBPS();

    /// @notice Thrown when user depositing zero assets amount
    error ZeroAssetsInAmount();

    /// @notice Thrown when user minting zero shares amount
    error ZeroSharesInAmount();

    /// @notice Thrown when the address is the zero address
    error ZeroAddress();

    /// @notice Thrown when the sender is not the vault
    error NotVault();

    /// @notice Thrown when the sender is not the guardian
    error NotGuardian();

    /// @notice Thrown when the sender is not the curator
    error NotCurator();

    /// @notice Thrown when trying to act before a timelock has expired
    error TimelockNotElapsed();

    /// @notice Thrown when the pending timelock update already exists, and it's not yet accepted
    error PendingTimelockExists();

    /// @notice Thrown when there is no pending change to act on
    error NoPendingChange();

    /// @notice Thrown when the timelock duration is invalid
    error InvalidTimelock();

    /// @notice Thrown when vault depositing zero assets amount in the strategy
    error ZeroAssetsStrategyInAmount();

    /// @notice Thrown when the timelock duration is greater than the maximum allowed
    error MaxTimelockExceeded();

    /// @notice Thrown when the timelock duration is less than the minimum allowed
    error MinTimelockNotReached();

    /// @notice Thrown when the storage value is already set.
    error AlreadySet();

    /// @notice Thrown when the vault fee share is not in the valid range (0 to 10_000 bps).
    error InvalidVaultFeeShare();

    /// @notice Thrown when the strategy is not valid (not connected to the vault or strategy has wrong asset).
    error InvalidStrategy();

    /// @notice Thrown when the strategy cap is zero.
    error ZeroStrategyCap();

    /// @notice Thrown when the pending strategy update already exists, and it's not yet accepted.
    error PendingStrategyExists();

    /// @notice Thrown when the strategy is not enabled.
    error StrategyNotEnabled();

    /// @notice Thrown when the pending strategy cap update already exists, and it's not yet accepted.
    error PendingStrategyCapExists();

    /// @notice Thrown when trying to submit a strategy that already exists.
    error StrategyAlreadyExists();

    /// @notice Thrown when the pending guardian update already exists, and it's not yet accepted.
    error PendingGuardianExist();

    /// @notice Thrown when the queue length is greater than the maximum allowed.
    error MaxQueueLengthExceeded();

    /// @notice Thrown when the strategy is already in the queue.
    error StrategyAlreadyInQueue();

    /// @notice Thrown when all the strategy caps are reached during the assets allocation.
    error AllCapsReached();

    /// @notice Thrown when there is not enough liquidity in strategies to withdraw the requested assets.
    error NotEnoughLiquidity();
}