// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title EventsLib
/// @author @ohMySol
/// @notice Library of events for the project contracts
library EventsLib {
    /// @dev Emitted when a new vault is created.
    /// @param vault The address of the newly created vault.
    /// @param creator The address of the creator of the vault.
    /// @param vaultOwner The address of the owner of the vault.
    /// @param asset The address of the underlying asset of the vault.
    /// @param name The name of the vault.
    /// @param symbol The symbol of the vault.
    /// @param vaultFee The vault fee in basis points.
    /// @param feeRecipient The address of the fee recipient.
    /// @param timelock The timelock duration in seconds.
    event VaultCreated(
        address indexed vault,
        address indexed creator,
        address indexed vaultOwner,
        address asset,
        string name,
        string symbol,
        uint256 vaultFee,
        address feeRecipient,
        uint256 timelock
    );

    /// @dev Emitted when the curator is updated.
    /// @param newCurator The address of the new curator.
    event CuratorUpdated(address indexed newCurator);

    /// @dev Emitted when the new allocator is set.
    /// @param newAllocator The address of the new allocator.
    /// @param newIsAllocator The flag set to the allocator address.
    event AllocatorSet(address indexed newAllocator, bool newIsAllocator);
     
    /// @dev Emitted when the fee is updated.
    /// @param newFee The new fee in basis points.   
    event FeeUpdated(uint256 newFee);

    /// @dev Emitted when the fee recipient is updated.
    /// @param newFeeRecipient The address of the new fee recipient.
    event FeeRecipientUpdated(address indexed newFeeRecipient);

    /// @dev Emitted when the guardian is updated.
    /// @param newGuardian The address of the new guardian.
    event GuardianUpdated(address indexed newGuardian);

    /// @dev Emitted when the guardian update is submitted.
    /// @param newGuardian The address of the new guardian.
    event GuardianSubmitted(address indexed newGuardian);

    /// @dev Emitted when the timelock update is submitted.
    /// @param newTimelock The new timelock duration.
    event TimelockSubmitted(uint256 newTimelock);

    /// @dev Emitted when the strategy is submitted.
    /// @param strategy The address of the strategy.
    /// @param strategyCap The cap of the strategy.
    event StrategySubmitted(address indexed strategy, uint256 strategyCap);

    /// @dev Emitted when the strategy cap is submitted.
    /// @param strategy The address of the strategy.
    /// @param newSupplyCap The new supply cap of the strategy.
    event StrategyCapSubmitted(address indexed strategy, uint256 newSupplyCap);

    /// @dev Emitted when the pending guardian update is revoked.
    /// @param revoker The address of the revoker.
    event PendingGuardianRevoked(address indexed revoker);

    /// @dev Emitted when the pending timelock update is revoked.
    /// @param revoker The address of the revoker.
    event PendingTimelockRevoked(address indexed revoker);

    /// @dev Emitted when the pending strategy update is revoked.
    /// @param revoker The address of the revoker.
    event PendingStrategyRevoked(address indexed revoker);

    /// @dev Emitted when the pending strategy cap update is revoked.
    /// @param revoker The address of the revoker.
    event PendingStrategyCapRevoked(address indexed revoker);

    /// @dev Emitted when the timelock is set.
    /// @param sender The address of the sender.
    /// @param newTimelock The new timelock duration.
    event TimelockSet(address indexed sender, uint256 newTimelock);

    /// @dev Emitted when the strategy is set.
    /// @param strategy The address of the strategy.
    /// @param strategyCap The cap of the strategy.
    event StrategySet(address indexed strategy, uint256 strategyCap);

    /// @dev Emitted when the last total assets is updated.
    /// @param newLastTotalAssets The new last total assets.
    event LastTotalAssetsUpdated(uint256 newLastTotalAssets);

    /// @dev Emitted when the vault fee share is updated.
    /// @param newVaultFeeShare The new vault fee share in basis points.
    event VaultFeeShareUpdated(uint256 newVaultFeeShare);

    /// @dev Emitted when the interest is accrued.
    /// @param newTotalAssets The new total assets.
    /// @param feeShares The fee shares.
    event AccrueInterest(uint256 newTotalAssets, uint256 feeShares);

    /// @dev Emitted when the strategy cap is updated.
    /// @param strategy The address of the strategy.
    /// @param newStrategyCap The new strategy cap.
    event StrategyCapUpdated(address indexed strategy, uint256 newStrategyCap);

    /// @dev Emitted when the supply queue is set.
    /// @param newSupplyQueue The new supply queue.
    event SetSupplyQueue(address[] indexed newSupplyQueue);

    /// @dev Emitted when the withdraw queue is set.
    /// @param newWithdrawQueue The new withdraw queue.
    event SetWithdrawQueue(address[] indexed newWithdrawQueue);

    /// @dev Emitted when a strategy is disabled.
    /// @param strategy The address of the disabled strategy.
    event StrategyDisabled(address indexed strategy);
}