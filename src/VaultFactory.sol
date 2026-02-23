// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IVaultFactory} from "./interfaces/IVaultFactory.sol";
import {IVault} from "./interfaces/IVault.sol";

import {Vault} from "./Vault.sol";

import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {EventsLib} from "./libraries/EventsLib.sol";

/// @title VaultFactory
/// @notice VaultFactory is a factory contract for creating new vaults
/// @dev This contract allows to create new `Vault` vaults and index them
contract VaultFactory is IVaultFactory {
    /* STORAGE */
    
    /// @inheritdoc IVaultFactory
    mapping (address => bool) public isValidVault;

    /* EXTERNAL */

    /// @inheritdoc IVaultFactory
    function createVault(
        address _vaultOwner,
        address _asset, 
        string memory _name, 
        string memory _symbol,
        uint256 _vaultFee,
        address _feeRecipient
    ) external returns (IVault vault) {
        vault = new Vault(_vaultOwner, _asset, _name, _symbol, _vaultFee, _feeRecipient);
        isValidVault[address(vault)] = true;

        emit EventsLib.VaultCreated(
            address(vault),
            msg.sender,
            _vaultOwner,
            _asset,
            _name,
            _symbol,
            _vaultFee,
            _feeRecipient
        );
    }
}