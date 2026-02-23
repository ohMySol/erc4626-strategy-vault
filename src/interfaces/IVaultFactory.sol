// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;
import {IVault} from "./IVault.sol";

/// @title IVaultFactory
/// @notice IVaultFactory interface for the VaultFactory contract
interface IVaultFactory {
    /// @notice Returns true if the vault is valid (means it was deployed by valid VaultFactory), false otherwise.
    /// @param vault The address of the vault to check.
    function isValidVault(address vault) external view returns (bool);

    /// @notice Creates a new vault and returns the newly deployed vault instance
    ///
    /// @param _vaultOwner The address of the owner of the vault
    /// @param _asset The address of the underlying asset
    /// @param _name The name of the vault
    /// @param _symbol The symbol of the vault
    /// @param _vaultFee The vault fee in basis points
    /// @param _feeRecipient The address of the fee recipient
    /// @return vault The newly deployed vault instance
    ///
    /// @dev Deploy new `Vault` contract, index it and emit `VaultCreated` event.
    function createVault(
        address _vaultOwner,
        address _asset, 
        string memory _name, 
        string memory _symbol,
        uint256 _vaultFee,
        address _feeRecipient
    ) external returns (IVault vault);
}