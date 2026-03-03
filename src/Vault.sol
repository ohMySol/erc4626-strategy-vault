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
    /// @dev Can be paused by the owner in case of emergency.
    function deposit(uint256 assets, address receiver) public virtual override whenNotPaused returns (uint256) {
        return super.deposit(assets, receiver);        
    }

    /// @inheritdoc IERC4626
    /// @dev Can be paused by the owner in case of emergency.
    function mint(uint256 shares, address receiver) public virtual override whenNotPaused returns (uint256) {
       return super.mint(shares, receiver);
    }

    /// @inheritdoc IERC4626
    /// @dev Can be paused by the owner in case of emergency.
    function withdraw(uint256 assets, address receiver, address owner) public virtual override whenNotPaused returns (uint256) {
        return super.withdraw(assets, receiver, owner);
    }

    /// @inheritdoc IERC4626
    /// @dev Can be paused by the owner in case of emergency.
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

    /// @notice Deposits `assets` on behalf of the `owner` and sends in exchange the corresponding number of shares to `receiver`.
    /// @dev This function is used inside `depositWithPermit` function to deposit assets on behalf of the `owner`
    /// and send in exchange the corresponding number of shares to `receiver`.
    /// 
    /// @param owner The owner of the assets.
    /// @param assets The amount of assets to deposit.
    /// @param receiver The address to receive the shares.
    /// @return The amount of shares the user will receive.
    function _depositFrom(address owner, uint256 assets, address receiver) internal returns (uint256) {
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) {
            revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
        }
    
        uint256 shares = previewDeposit(assets);
        super._deposit(owner, receiver, assets, shares);
        
        return shares;
    }

    /// @notice Mints `shares` amount of shares to `receiver` in exchange for assets transferred on behalf of the `owner`. 
    /// @dev This function is used inside `mintWithPermit` function to mint `shares` to `receiver` and send in exchange 
    /// the corresponding number of assets on behalf of the `owner` to the vault contract.
    /// 
    /// @param owner The owner of the assets.
    /// @param shares The amount of shares to mint.
    /// @param receiver The address to receive the shares.
    /// @return The amount of assets the user sent.
    function _mintFrom(address owner, uint256 shares, address receiver) internal returns (uint256) {
        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
        }
        
        uint256 assets = previewMint(shares);
        super._deposit(owner, receiver, assets, shares);
        
        return assets;
    }

    /* ERC4626 (INTERNAL) */

    /// @inheritdoc ERC4626
    /// @dev Returns the number of decimals to add to the underlying asset's decimals.
    function _decimalsOffset() internal view virtual override returns (uint8) {
        return 9;
    }
}