// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Vault} from "../../src/Vault.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Thin wrapper that exposes Vault internals for unit testing.
contract VaultHarness is Vault {
    constructor(
        address _owner,
        address _asset,
        string memory _name,
        string memory _symbol,
        uint256 _vaultFee,
        address _feeRecipient,
        uint256 _vaultFeeShare,
        uint256 _timelock
    ) Vault(_owner, _asset, _name, _symbol, _vaultFee, _feeRecipient, _vaultFeeShare, _timelock) {}

    function exposed_calculateFeeAndTotals() external view returns (
        uint256 newTotalAssets,
        uint256 newLostAssets,
        uint256 totalStrategyYield,
        uint256[] memory strategyYields,
        uint256[] memory strategyCurrentAssets,
        uint256 feeShares
    ) {
        return _calculateFeeAndTotals();
    }

    function exposed_accrueInterest() external {
        _accrueInterest();
    }

    function exposed_maxDeposit() external view returns (uint256) {
        return _maxDeposit();
    }

    function exposed_maxWithdraw(address owner) external view returns (uint256 assets, uint256 newTotalSupply, uint256 newTotalAssets) {
        return _maxWithdraw(owner);
    }

    function exposed_withdrawalLiquidityGap(uint256 assets) external view returns (uint256) {
        return _withdrawalLiquidityGap(assets);
    }

    function exposed_convertToSharesWithTotals(
        uint256 assets,
        uint256 newTotalSupply,
        uint256 newTotalAssets,
        Math.Rounding rounding
    ) external view returns (uint256) {
        return _convertToSharesWithTotals(assets, newTotalSupply, newTotalAssets, rounding);
    }

    function exposed_convertToAssetsWithTotals(
        uint256 shares,
        uint256 newTotalSupply,
        uint256 newTotalAssets,
        Math.Rounding rounding
    ) external view returns (uint256) {
        return _convertToAssetsWithTotals(shares, newTotalSupply, newTotalAssets, rounding);
    }

    function exposed_decimalsOffset() external view returns (uint8) {
        return _decimalsOffset();
    }

    function getStrategies() external view returns (address[] memory) {
        return _strategies;
    }

    function getSupplyQueue() external view returns (address[] memory) {
        return _supplyQueue;
    }

    function getWithdrawQueue() external view returns (address[] memory) {
        return _withdrawQueue;
    }
}
