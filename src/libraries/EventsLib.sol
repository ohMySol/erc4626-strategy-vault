// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title EventsLib
/// @notice Library of events for the Vault contract
library EventsLib {
    /// @notice Emitted when a new vault is created
    /// @param vault The address of the newly created vault
    /// @param creator The address of the creator of the vault
    /// @param vaultOwner The address of the owner of the vault
    /// @param asset The address of the underlying asset of the vault
    /// @param name The name of the vault
    /// @param symbol The symbol of the vault
    /// @param vaultFee The vault fee in basis points
    /// @param feeRecipient The address of the fee recipient
    event VaultCreated(
        address indexed vault,
        address indexed creator,
        address indexed vaultOwner,
        address asset,
        string name,
        string symbol,
        uint256 vaultFee,
        address feeRecipient
    );
}