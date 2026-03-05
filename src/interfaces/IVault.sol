// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IVault
/// @author @ohMySol
/// @notice Interface that defines the functions for the Vault contract.
interface IVault {
    /// @notice Vault fee in basis points. Can not be greater than 100%(10_000 BPS).
    function FEE_BPS() external view returns (uint256);
    
    /// @notice Vault fee recipient address. Can not be the zero address.
    function FEE_RECIPIENT() external view returns (address);
    
    /// @notice Deposit `assets` underlying tokens on behalf of the `owner` and send in exchange the corresponding number of vault shares to `receiver`.
    /// This function is using a gasless transaction mechanism, that allows the `owner` to sign a permit signature off chain(using ERC2612) 
    /// before calling this function, and provide the signature components.
    ///
    /// This function can be used to allow relayers to deposit assets on behalf of the user.
    ///
    /// @param assets The amount of assets to deposit.
    /// @param owner The owner of the underlying assets.
    /// @param receiver The address to receive the shares.
    /// @param deadline The deadline for the permit.
    /// @param permitV The v component of the signature.
    /// @param permitR The r component of the signature.
    /// @param permitS The s component of the signature.
    ///
    /// @dev The `owner` must sign a permit signature off chain before calling this function,
    /// and provide the signature components.
    ///
    /// Important: This function can be called only if the underlying asset supports ERC2612 permit functionality.
    ///
    /// @return The amount of shares the user will receive.
    function depositWithPermit(
        uint256 assets, 
        address owner,
        address receiver, 
        uint256 deadline,
        uint8 permitV, 
        bytes32 permitR, 
        bytes32 permitS
    ) external returns (uint256);

    /// @notice Mints exactly `shares` vault shares to `receiver` in exchange for assets transferred on behalf of the `owner`. 
    /// This function is using a gasless transaction mechanism, that allows the `owner` to sign a permit signature off chain(using ERC2612) 
    /// before calling this function, and provide the signature components.
    ///
    /// This function can be used to allow relayers to mint shares on behalf of the user.
    ///
    /// @param shares The amount of shares to mint.
    /// @param owner The owner of the underlying assets.
    /// @param receiver The address to receive the shares.
    /// @param deadline The deadline for the permit.
    /// @param permitV The v component of the signature.
    /// @param permitR The r component of the signature.
    /// @param permitS The s component of the signature.
    ///
    /// @dev The `owner` must sign a permit signature off chain before calling this function,
    /// and provide the signature components.
    ///
    /// Important: This function can be called only if the underlying asset supports ERC2612 permit functionality.
    ///
    /// @return The amount of assets the user will send.
    function mintWithPermit(
        uint256 shares, 
        address owner,
        address receiver, 
        uint256 deadline, 
        uint8 permitV, 
        bytes32 permitR, 
        bytes32 permitS
    ) external returns (uint256);
    
    /// @notice Pauses the vault. 
    /// @dev Only the owner can pause the vault.
    function pause() external;

    /// @notice Unpauses the vault.
    /// @dev Only the owner can unpause the vault.
    function unpause() external;
}