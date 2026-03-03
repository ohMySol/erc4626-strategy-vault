// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ErrorsLib} from "./ErrorsLib.sol";

/// @notice A struct to store a pending value that can be set at a future time.
/// @param value The pending value to set
/// @param validAt The timestamp at which the value becomes valid
struct PendingUint192 {
    uint192 value;
    uint64 validAt;
}

/// @notice A struct to store a pending address that can be set at a future time.
/// @param value The pending value to set
/// @param validAt The timestamp at which the value becomes valid
struct PendingAddress {
    address value;
    uint64 validAt;
}

/// @title PendingLib
/// @notice Library for managing pending values and their validity timestamps.
/// Before doing the critical update in the vault, such as adding a new strategy,
/// or changing the caps, this change is stored in a pending state(under timelock). 
/// This allows users to exit the vault if they don't like th change or guardian to
/// revert the change if it's not safe.
library PendingLib {
    /// @notice Updates the `pending` `value` with a `newValue` and its corresponding `validAt` timestamp.
    /// @param pending The pending `PendingUint192` struct to update
    /// @param newValue The new value to set
    /// @param timelockDuration The duration of the timelock
    function update(PendingUint192 memory pending, uint192 newValue, uint256 timelockDuration) internal view {
        pending.value = newValue;
        pending.validAt = uint64(block.timestamp + timelockDuration);
    }

    /// @notice Updates the `pending` `value` with a `newValue` and its corresponding `validAt` timestamp.
    /// @param pending The pending `PendingAddress` struct to update
    /// @param newValue The new value to set
    /// @param timelockDuration The duration of the timelock
    function update(PendingAddress memory pending, address newValue, uint256 timelockDuration) internal view {
        pending.value = newValue;
        pending.validAt = uint64(block.timestamp + timelockDuration);
    }
}