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

    /// @notice Thrown when user depositing zero assets amount in the strategy
    error ZeroAssetsStrategyInAmount();
}