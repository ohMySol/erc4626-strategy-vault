// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IStrategy, StrategyConfig} from "./IStrategy.sol";

/// @title IVault
/// @author @ohMySol
/// @notice Interface that defines the functions for the Vault contract.
interface IVault {
    /// @notice Performance fee in basis points. Can not be greater than `MAX_FEE`.
    function fee() external view returns (uint96);
    
    /// @notice Performance fee recipient address. Can not be the zero address.
    function feeRecipient() external view returns (address);

    /// @notice Address of the curator.
    function curator() external view returns (address);

    /// @notice Address of the guardian.
    function guardian() external view returns (address);

    /// @notice Global timelock duration in seconds for critical changes.
    function timelock() external view returns (uint256);

    /// @notice Pending `pendingGuardian` address and `validAt` timestamp when it becomes valid.
    function pendingGuardian() external view returns (address pendingGuardian, uint64 validAt);

    /// @notice Pending `newTimelock` duration and `validAt` timestamp when it becomes valid.
    function pendingTimelock() external view returns (uint192 pendingTimelock, uint64 validAt);

    /// @notice Configuration of a strategy connected to the vault.
    /// @param strategy The address of the strategy.
    /// @return cap The maximum asset allocation for the strategy.
    /// @return enabled Whether the strategy is enabled or not.
    /// @return proposed Whether the strategy is proposed or not (means it's waiting for approval).
    /// @return lastAccrualTimestamp The timestamp of the last accrual.
    /// @return strategyOwnerFeeBPS The percentage of performance fee that goes to the strategy owner.
    /// @return lastTotalAssets The most recent total assets of the strategy.
    function strategyConfig(address strategy) external view returns (
        uint184 cap,
        bool enabled,
        bool proposed,
        uint64 lastAccrualTimestamp,
        uint96 strategyOwnerFeeBPS,
        uint256 lastTotalAssets
    );

    /// @notice Deposit `assets` underlying tokens on behalf of the `owner` and send in exchange the corresponding number of vault shares to `receiver`.
    /// This function is using a gasless transaction mechanism, that allows the `owner` to sign a permit signature off chain(using ERC2612) 
    /// before calling this function, and provide the signature components.
    ///
    /// This function can be used to allow relayers to deposit assets on behalf of the user.
    ///
    /// @dev The `owner` must sign a permit signature off chain before calling this function,
    /// and provide the signature components.
    ///
    /// Important: This function can be called only if the underlying asset supports ERC2612 permit functionality.
    ///
    /// @param assets The amount of assets to deposit.
    /// @param owner The owner of the underlying assets.
    /// @param receiver The address to receive the shares.
    /// @param deadline The deadline for the permit.
    /// @param permitV The v component of the signature.
    /// @param permitR The r component of the signature.
    /// @param permitS The s component of the signature.
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
    /// @dev The `owner` must sign a permit signature off chain before calling this function,
    /// and provide the signature components.
    ///
    /// Important: This function can be called only if the underlying asset supports ERC2612 permit functionality.
    ///
    /// @param shares The amount of shares to mint.
    /// @param owner The owner of the underlying assets.
    /// @param receiver The address to receive the shares.
    /// @param deadline The deadline for the permit.
    /// @param permitV The v component of the signature.
    /// @param permitR The r component of the signature.
    /// @param permitS The s component of the signature.
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

    /// @notice Sets a new curator address.
    /// @dev Only the owner can set a new curator address.
    function setCurator(address newCurator) external;

    /// @notice Submits a `newGuardian` address under timelock.
    /// @dev Only the owner can submit a `newGuardian` guardian. 
    /// The `newGuardian` can be accepted after the timelock has elapsed.
    /// IMPORTANT: 
    /// - The `newGuardian` address can not be the zero address.
    /// - The `newGuardian` address must be different from the current guardian.
    ///
    /// @param newGuardian The new guardian address.
    function submitGuardian(address newGuardian) external;

    /// @notice Submits a `newTimelock` duration. Increases are instant, decreases are timelocked.
    /// @dev Only the owner can call this function.
    /// IMPORTANT: 
    /// - The `newTimelock` duration can not be zero.
    /// - If there is an active pending timelock (means not yet accepted), the function will revert.
    ///
    /// @param newTimelock The new timelock duration in seconds.
    function submitTimelock(uint256 newTimelock) external;

    /// @notice Sets a new performance fee for the vault in basis points.
    /// @dev Only the owner can call this function.
    /// IMPORTANT: 
    /// - The `newFee` can not be greater than `MAX_FEE`.
    /// - If the current `fee` is equal to the `newFee`, the function will revert.
    ///
    /// @param newFee The new performance fee in basis points.
    function setFee(uint256 newFee) external;

    /// @notice Sets a new performance fee recipient.
    /// @dev Only the owner can call this function.
    /// IMPORTANT: 
    /// - The `newFeeRecipient` can not be the zero address.
    /// - If the current `feeRecipient` is equal to the `newFeeRecipient`, the function will revert.
    ///
    /// @param newFeeRecipient The new performance fee recipient address.
    function setFeeRecipient(address newFeeRecipient) external;

    /// TODO: AWAITS FINISHING NATSPEC
    /// @notice Accepts the pending guardian after the timelock has elapsed.
    /// @dev Can be called by anyone.
    function acceptGuardian() external;

    /// TODO: AWAITS FINISHING NATSPEC
    /// @notice Accepts a pending timelock decrease after the timelock has elapsed.
    /// @dev Can be called by anyone.
    function acceptTimelock() external;

    /// TODO: AWAITS FINISHING NATSPEC
    /// @notice Guardian can revoke a pending guardian change.
    function revokePendingGuardian() external;

    /// TODO: AWAITS FINISHING NATSPEC
    /// @notice Guardian can revoke a pending timelock change.
    function revokePendingTimelock() external;
}