// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {BaseStrategy} from "../../src/BaseStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Minimal strategy for testing: holds tokens, reports balance, and can simulate yield/loss.
contract MockStrategy is BaseStrategy {
    using SafeERC20 for IERC20;

    uint256 private _strategyAssets;
    bool public failOnDeposit;
    bool public failOnWithdraw;
    bool public partialWithdraw;
    uint256 public partialWithdrawBps; // e.g. 5000 = return 50%

    constructor(address _vault, address _strategyOwner) BaseStrategy(_vault, _strategyOwner) {}

    function _deposit(uint256 assets) internal override {
        if (failOnDeposit) revert("MockStrategy: deposit failed");
        IERC20(asset).safeTransferFrom(vault, address(this), assets);
        _strategyAssets += assets;
    }

    function _withdraw(uint256 assets, address to) internal override returns (uint256) {
        if (failOnWithdraw) revert("MockStrategy: withdraw failed");

        uint256 actual = assets;
        if (partialWithdraw) {
            actual = assets * partialWithdrawBps / 10_000;
        }
        if (actual > _strategyAssets) actual = _strategyAssets;

        _strategyAssets -= actual;
        IERC20(asset).safeTransfer(to, actual);
        return actual;
    }

    function _totalAssets() internal view override returns (uint256) {
        return _strategyAssets;
    }

    /* TEST HELPERS (not called by the vault) */

    function simulateYield(uint256 amount) external {
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        _strategyAssets += amount;
    }

    function simulateLoss(uint256 amount) external {
        if (amount > _strategyAssets) amount = _strategyAssets;
        _strategyAssets -= amount;
        IERC20(asset).safeTransfer(msg.sender, amount);
    }

    function setFailOnDeposit(bool fail) external {
        failOnDeposit = fail;
    }

    function setFailOnWithdraw(bool fail) external {
        failOnWithdraw = fail;
    }

    function setPartialWithdraw(bool enabled, uint256 bps) external {
        partialWithdraw = enabled;
        partialWithdrawBps = bps;
    }
}
