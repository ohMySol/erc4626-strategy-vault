// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC4626,ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IVault} from "./interfaces/IVault.sol";

/// @title Vault
/// @notice This is a ERC4626 vault contract, which allows users deposit assets and earn interest on them.
/// Vault takes entry fee which will be sent to the fee recipient. The fee is taken during the deposit or mint operation.
contract Vault is ERC4626, Ownable2Step, Pausable, IVault {
    using SafeERC20 for IERC20;

    /* IMMUTABLES */

    /// @inheritdoc IVault
    uint256 public immutable FEE_BPS;
    
    /// @inheritdoc IVault
    address public immutable FEE_RECIPIENT; 
    
    /* CONSTRUCTOR */

    /// @dev Intiializes the contract
    /// @param _asset The address of the underlying asset
    /// @param _name The name of the vault
    /// @param _symbol The symbol of the vault 
    /// @param _vaultFee The vault fee in basis points
    /// @param _feeRecipient The address of the fee recipient
    constructor(
        address _owner,
        address _asset, 
        string memory _name, 
        string memory _symbol,
        uint256 _vaultFee,
        address _feeRecipient
    )
     ERC4626(IERC20(_asset)) 
     ERC20(_name, _symbol)
     Ownable(_owner)
    {
        if (_asset == address(0)) revert ErrorsLib.ZeroAddress();
        if (_feeRecipient == address(0)) revert ErrorsLib.ZeroAddress();
        if (_vaultFee >= 10_000) revert ErrorsLib.InvalidFeeBPS();
        FEE_BPS = _vaultFee;
        FEE_RECIPIENT = _feeRecipient;
    }

    /* ERC4626 (PUBLIC) */

    /// @inheritdoc IERC4626
    /// @dev Calculates the amount of shares for a given amount of assets - `FEE_BPS` entry fee.
    /// @return The amount of shares the user will receive after the fee is taken.
    function previewDeposit(uint256 assets) public view virtual override returns (uint256) {
        uint256 fee = _fee(assets);
        return super.previewDeposit(assets - fee);
    }

    /// @inheritdoc IERC4626
    /// @dev Calculates the amount of assets needed to mint a given amount of shares, including the `FEE_BPS` entry fee.
    /// @return The amount of assets(including fee) the user must send to mint the requested shares.
    function previewMint(uint256 shares) public view virtual override returns (uint256) {
        // Calculate net assets needed (without fee) to mint the requested shares
        uint256 netAssets = super.previewMint(shares);
        uint256 denominator = 10000 - FEE_BPS;
        // Gross up to include the fee
        uint256 assetsGross = (netAssets * 10000 + denominator - 1) / denominator;
        return assetsGross;
    }

    /// @inheritdoc IERC4626
    /// @dev Deposits assets into the vault, and take a deposit `FEE_BPS` fee.
    /// The fee is sent to `FEE_RECIPIENT`.
    function deposit(uint256 assets, address receiver) public virtual override whenNotPaused returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        uint256 fee = _fee(assets);
        if (fee > 0) {
            IERC20(asset()).safeTransferFrom(msg.sender, FEE_RECIPIENT, fee);
        }
        
        uint256 shares = previewDeposit(assets);
        super._deposit(_msgSender(), receiver, assets - fee, shares);
        
        return shares;
    }

    /// @inheritdoc IERC4626
    /// @dev Mints shares to `receiver` by taking the required assets (including fee) from the caller.
    /// The fee is sent to `FEE_RECIPIENT`.
    function mint(uint256 shares, address receiver) public virtual override whenNotPaused returns (uint256) {
        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
        }
        
        uint256 assetsGross = previewMint(shares);
        uint256 fee = _fee(assetsGross);
        if (fee > 0) {
            IERC20(asset()).safeTransferFrom(msg.sender, FEE_RECIPIENT, fee);
        }
        
        super._deposit(_msgSender(), receiver, assetsGross - fee, shares);
        
        return assetsGross;
    }

    /// @inheritdoc IERC4626
    function withdraw(uint256 assets, address receiver, address owner) public virtual override whenNotPaused returns (uint256) {
        return super.withdraw(assets, receiver, owner);
    }

    /// @inheritdoc IERC4626
    function redeem(uint256 shares, address receiver, address owner) public virtual override whenNotPaused returns (uint256) {
        return super.redeem(shares, receiver, owner);
    }

    /* GASLESS PUBLIC FUNCTIONS */

    /// @inheritdoc IVault
    function depositWithPermit(
        uint256 assets, 
        address owner,
        address receiver, 
        uint256 deadline, 
        uint8 permitV, 
        bytes32 permitR, 
        bytes32 permitS
    ) public virtual whenNotPaused returns (uint256) {
        if (assets == 0) revert ErrorsLib.ZeroAssetsInAmount();
        IERC20Permit(asset()).permit(
            owner, 
            address(this), 
            assets, 
            deadline, 
            permitV, 
            permitR, 
            permitS
        );
        
        return _depositFrom(owner,assets, receiver);
    }

    /// @inheritdoc IVault
    function mintWithPermit(
        uint256 shares, 
        address owner,
        address receiver, 
        uint256 deadline, 
        uint8 permitV, 
        bytes32 permitR, 
        bytes32 permitS
    ) public virtual whenNotPaused returns (uint256) {
        if (shares == 0) revert ErrorsLib.ZeroSharesInAmount();
        uint256 grossAssets = previewMint(shares);
        IERC20Permit(asset()).permit(
            owner, 
            address(this), 
            grossAssets, 
            deadline, 
            permitV, 
            permitR, 
            permitS
        );
        
        return _mintFrom(owner, shares, receiver);
    }

    /* ONLY OWNER FUNCTIONS */

    /// @inheritdoc IVault
    function pause() public onlyOwner {
        _pause();
    }

    /// @inheritdoc IVault
    function unpause() public onlyOwner {
        _unpause();
    }

    /* INTERNAL FUNCTIONS */

    /// @notice Calculates the fee for a given amount of assets.
    /// @param assets The amount of assets to calculate the fee for.
    /// @return The fee amount.
    function _fee(uint256 assets) internal view returns (uint256) {
        return (assets * FEE_BPS) / 10000;
    }

    /// @notice Deposits assets from `owner` to `receiver` and takes the `FEE_BPS` fee.
    /// 
    /// @param owner The owner of the assets.
    /// @param assets The amount of assets to deposit.
    /// @param receiver The address to receive the shares.
    /// @return The amount of shares the user will receive after the fee is taken.
    function _depositFrom(address owner, uint256 assets, address receiver) internal returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }

        uint256 fee = _fee(assets);
        if (fee > 0) {
            IERC20(asset()).safeTransferFrom(owner, FEE_RECIPIENT, fee);
        }
        
        uint256 shares = previewDeposit(assets);
        super._deposit(owner, receiver, assets - fee, shares);
        
        return shares;
    }

    /// @notice Takes assets from `owner` and mints shares to `receiver` and takes the `FEE_BPS` fee.
    /// 
    /// @param owner The owner of the assets.
    /// @param shares The amount of shares to mint.
    /// @param receiver The address to receive the shares.
    /// @return The amount of assets the user will send (including fee).
    function _mintFrom(address owner, uint256 shares, address receiver) internal returns (uint256) {
        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
        }
        
        uint256 assetsGross = previewMint(shares);
        uint256 fee = _fee(assetsGross);
        if (fee > 0) {
            IERC20(asset()).safeTransferFrom(owner, FEE_RECIPIENT, fee);
        }
        
        super._deposit(owner, receiver, assetsGross - fee, shares);
        
        return assetsGross;
    }

    /* ERC4626 (INTERNAL) */

    /// @inheritdoc ERC4626
    /// @dev Returns the number of decimals to add to the underlying asset's decimals.
    function _decimalsOffset() internal view virtual override returns (uint8) {
        return 9;
    }
}