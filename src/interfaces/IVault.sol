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

    /// @notice Vault's share of the performance fee (the rest is the strategist pool).
    /// @dev This fee share is deducted from the performance fee and sent to `feeRecipient`.
    /// There is no limit on fee share for vault, so it is up to the vault owner to set it.
    function vaultFeeShare() external view returns (uint96);

    /// @notice Address of the curator.
    function curator() external view returns (address);

    /// @notice Address of the guardian.
    function guardian() external view returns (address);

    /// @notice Global timelock duration in seconds for critical changes.
    function timelock() external view returns (uint256);

    /// @notice Pending `pendingGuardian` address and `validAt` timestamp when it becomes valid.
    function pendingGuardian() external view returns (address pendingGuardian, uint64 validAt);

    /// @notice Pending `pendingTimelock` duration and `validAt` timestamp when it becomes valid.
    function pendingTimelock() external view returns (uint192 pendingTimelock, uint64 validAt);

    /// @notice Pending `pendingStrategyCap` value and `validAt` timestamp when it becomes valid.
    /// @param strategy The address of the strategy.
    /// @return pendingStrategyCap The pending strategy cap value.
    /// @return validAt The timestamp when the pending strategy cap becomes valid.
    function pendingStrategy(address strategy) external view returns (uint192 pendingStrategyCap, uint64 validAt);

    /// @notice Pending `pendingStrategyCap` address and `validAt` timestamp when it becomes valid.
    /// @dev The difference from the previous `pendingStrategy` is that this is a pending update of the strategy cap,
    /// while the previous is a pending addition of the strategy.
    /// @param strategy The address of the strategy.
    /// @return pendingStrategyCap The pending strategy cap value.
    /// @return validAt The timestamp when the pending strategy cap becomes valid.
    function pendingStrategyCap(address strategy) external view returns (uint192 pendingStrategyCap, uint64 validAt);

    /// @notice Total amount of lost assets due to failed strategies.
    function lostAssets() external view returns (uint256);

    /// @notice Last total assets of the vault before the last accrual.
    function lastTotalAssets() external view returns (uint256);

    /// @notice Configuration of a strategy connected to the vault.
    /// @param strategy The address of the strategy.
    /// @return cap The maximum asset allocation for the strategy.
    /// @return enabled Whether the strategy is enabled or not.
    /// @return lastAccrualTimestamp The timestamp of the last accrual.
    /// @return lastTotalAssets The most recent total assets of the strategy.
    function strategyConfig(address strategy) external view returns (
        uint184 cap,
        bool enabled,
        uint64 lastAccrualTimestamp,
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
    /// IMPORTANT: 
    /// - The `newCurator` address can not be the zero address.
    /// - The `newCurator` address must be different from the current curator.
    ///
    /// @param newCurator The new curator address.
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

    /// @notice Sets the vault's share of the performance fee (the rest is the strategist pool).
    /// @dev Only the owner can call this function. 
    /// IMPORTANT: 
    /// - If `newVaultFeeShare` value is greater than `MAX_VAULT_FEE_SHARE_BPS`, the function will revert.
    /// - If the current `vaultFeeShare` is equal to the `newVaultFeeShare`, the function will revert.
    ///
    /// @param newVaultFeeShare The new vault's share of the performance fee in basis points.
    function setVaultFeeShare(uint256 newVaultFeeShare) external;

    /// @notice Submits a `strategy` address and `strategyCap` value under timelock.
    /// @dev Only the curator can call this function.
    /// IMPORTANT: 
    /// - The `strategy` should be unique (no duplicates).
    /// - The `strategy` address can not be the zero address.
    /// - The `strategy` address must be connected to the vault.
    /// - The `strategy` address must be connected to the same asset as the vault.
    /// - The `strategyCap` value can not be zero.
    /// - If there is an active pending strategy (means not yet accepted), the function will revert.
    ///
    /// @param strategy The address of the strategy.
    /// @param strategyCap The strategy cap value.
    function submitStrategy(address strategy, uint256 strategyCap) external;

    /// @notice Submits a `newStrategyCap` value for a `strategy` under timelock.
    /// @dev Only the curator can call this function. If the `newStrategyCap` value is less than the current strategy cap,
    /// the function will set the strategy cap immediately. Otherwise, it will submit the new strategy cap under timelock.
    /// IMPORTANT: 
    /// - The `strategy` address should be enabled.
    /// - The `strategyCap` value can not be zero.
    /// - The `newStrategyCap` value can not be equal to the current strategy cap.
    /// - If there is an active pending strategy cap (means not yet accepted), the function will revert.
    ///
    /// @param strategy The address of the strategy.
    /// @param newStrategyCap The new strategy cap value.
    function submitStrategyCap(address strategy, uint256 newStrategyCap) external;

    /// @notice Accepts the pending guardian after the timelock has elapsed.
    /// @dev Can be called by anyone.
    function acceptGuardian() external;

    /// @notice Accepts a pending timelock.
    /// @dev Can be called by anyone.
    /// IMPORTANT: 
    /// - New timelock must not be greated than the MAX_TIMELOCK.
    /// - New timelock must not be less than the MIN_TIMELOCK.
    function acceptTimelock() external;

    /// @notice Accepts the pending strategy and its cap after the timelock has elapsed.
    /// @dev Can be called by anyone.
    function acceptStrategy(address strategy) external;

    /// @notice Accepts the pending strategy cap after the timelock has elapsed.
    /// @dev Can be called by anyone.
    function acceptStrategyCap(address strategy) external;

    /// @notice Revokes a pending guardian.
    /// @dev Can be called only by address with guardian role.
    /// IMPORTANT: 
    /// - If there is no pending guardian, the function will revert.
    function revokePendingGuardian() external;

    /// @notice Revokes a pending timelock.
    /// @dev Can be called only by address with guardian role.
    /// IMPORTANT: 
    /// - If there is no pending timelock, the function will revert.
    function revokePendingTimelock() external;
}