// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IStrategy} from "./interfaces/IStrategy.sol";
import {IERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";

/// @title BaseStrategy
/// @author @ohMySol
/// @notice Base contract for all strategies.
/// @dev This abstract contract implements the IStrategy interface and provides a base functionality for all strategies.
/// Each strategy contract that wants to be used by the vault contract must inherit from this contract.
///
/// IMPORTANT: Each strategy contract must implement the IStrategy interface.
abstract contract BaseStrategy is IStrategy {
    /* IMMUTABLES */

    /// @inheritdoc IStrategy
    address public immutable asset;

    /// @inheritdoc IStrategy
    address public immutable vault;
    
    /// @inheritdoc IStrategy
    address public immutable strategyOwner;

    /* MODIFIERS */

    /// @notice Modifier to check if the sender is the vault
    modifier onlyVault() {
        if (msg.sender != vault) revert ErrorsLib.NotVault();
        _;
    }

    /* CONSTRUCTOR */

    /// @dev Initializes the strategy
    /// @param _vault The address of the vault
    /// @param _strategyOwner The address of the strategy owner
    constructor(address _vault, address _strategyOwner) {
        if (_vault == address(0)) revert ErrorsLib.ZeroAddress();
        if (_strategyOwner == address(0)) revert ErrorsLib.ZeroAddress();
        
        asset = IERC4626(_vault).asset();
        vault = _vault;
        strategyOwner = _strategyOwner;
    }

    /* EXTERNAL FUNCTIONS */

    /// @inheritdoc IStrategy
    function deposit(uint256 assets) external onlyVault {
        if (assets == 0) revert ErrorsLib.ZeroAssetsStrategyInAmount();
        _deposit(assets);
    }

    /// @inheritdoc IStrategy
    function withdraw(uint256 assets, address to) external onlyVault returns (uint256) {
        return _withdraw(assets, to);
    }

    /// @inheritdoc IStrategy
    function totalAssets() external view returns (uint256) {
        return _totalAssets();
    }

    /* INTERNAL FUNCTIONS TO BE OVERRIDEN BY THE STRATEGY CONTRACT */

    /// @notice Internal abstract function to deposit assets into the strategy.
    /// @dev This function should be overriden by the strategy contract to implement the deposit logic.
    /// @param assets The amount of assets to deposit.
    function _deposit(uint256 assets) internal virtual;

    /// @notice Internal abstract function to withdraw assets from the strategy.
    /// @dev This function should be overriden by the strategy contract to implement the withdraw logic.
    /// 
    /// @param assets The amount of assets to withdraw.
    /// @param to The address to send the assets to.
    /// @return The amount of assets withdrawn.
    function _withdraw(uint256 assets, address to) internal virtual returns (uint256);

    /// @notice Internal abstract function to get the total assets of the strategy.
    /// @dev This function should be overriden by the strategy contract to implement the total assets logic.
    /// @return The total assets of the strategy.
    function _totalAssets() internal virtual view returns (uint256);
 }