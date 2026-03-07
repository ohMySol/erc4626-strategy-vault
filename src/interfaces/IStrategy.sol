// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @notice A struct to store the configuration of a strategy.
/// @param cap Max asset allocation for the strategy.
/// @param enabled Whether the strategy is enabled or not.
/// @param proposed Whether the strategy is proposed or not (means it's waiting for approval).
/// @param lastAccrualTimestamp The timestamp of the last accrual.
/// @param lastTotalAssets The most recent total assets of the strategy.
struct StrategyConfig {
    uint184 cap;
    bool enabled;
    bool proposed;
    uint64 lastAccrualTimestamp;
    uint256 lastTotalAssets;
}

/// @title IStrategy
/// @author @ohMySol
/// @notice Interface that defines the functions for a strategy contract.
/// Each strategy contract that wants to be used by the vault contract must implement this interface.
/// @dev The vault contract interacts with the strategy contract via IStrategy interface to deposit and withdraw assets.
interface IStrategy {
    /// @notice Address of the underlying asset for the strategy.
    function asset() external view returns (address);

    /// @notice Address of the vault contract that is using the strategy.
    function vault() external view returns (address);

    /// @notice Address of the strategy owner.
    function strategyOwner() external view returns(address);

    /// @notice Deposits `assets` into the strategy.
    /// @param assets The amount of assets to deposit.
    function deposit(uint256 assets) external;

    /// @notice Withdraws `assets` from the strategy and sends them to `to`.
    /// @param assets The amount of assets to withdraw.
    /// @param to The address to send the assets to.
    /// @return withdrawnAssets The amount of assets withdrawn.
    function withdraw(uint256 assets, address to) external returns (uint256 withdrawnAssets);

    /// @notice Returns the total assets of the strategy.
    function totalAssets() external view returns (uint256);
}
