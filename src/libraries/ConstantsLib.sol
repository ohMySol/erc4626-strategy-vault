// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title ConstantsLib
/// @author @ohMySol
/// @notice Library of constants for the project contracts
library ConstantsLib {
    /// @dev Maximum allowed performance fee in basis points (e.g. 2_000 = 20%).
    uint256 internal constant MAX_FEE = 2_000;

    /// @dev Maximum allowed vault fee share in basis points (e.g. 7_000 = 70%).
    uint256 internal constant MAX_VAULT_FEE_SHARE_BPS = 7_000;

    /// @dev Maximum allowed timelock duration in seconds.
    uint256 internal constant MAX_TIMELOCK = 1 weeks;

    /// @dev Minimum allowed timelock duration in seconds.
    uint256 internal constant MIN_TIMELOCK = 1 days;

    /// @dev BPS denominator (10_000 = 100%).
    uint256 internal constant BPS = 10_000;
}