// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
    IERC4626,
    ERC4626,
    ERC20,
    IERC20,
    SafeERC20,
    Math
} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {ErrorsLib} from "./libraries/ErrorsLib.sol";
import {EventsLib} from "./libraries/EventsLib.sol";
import {PendingLib, PendingUint192, PendingAddress} from "./libraries/PendingLib.sol";
import {ConstantsLib} from "./libraries/ConstantsLib.sol";


import {IVault} from "./interfaces/IVault.sol";
import {IStrategy, StrategyConfig} from "./interfaces/IStrategy.sol";

/// @title Vault
/// @author @ohMySol
/// @notice This is an ERC4626 vault contract, which allows users deposit assets and earn interest on them.
/// Assets will be allocated to different yield strategies by `Allocator`, and the strategies will be selected by the vault `Curator`.
/// Strategy can be created in a permissionless way, so anyone is allowed to create a strategy contract and propose it to include in the vault. 
/// Once strategy is approved by curator and included in the vault, the strategy owner can earn a portion of the performance fee which is taken
/// from the generated yield.
///
/// @dev This contract demonstrates an ERC4626 vault contract which can be connected to different yield strategies.
/// Each strategy contract that wants to be used by the vault contract must implement the `BaseStrategy` contract
/// by inheriting from it.
/// `BaseStrategy` contract implements the `IStrategy` interface and provides a base functionality for all strategies,
/// which is important for the vault contract to interact with the strategies.
///
/// IMPORTANT: 
/// - This contract is not production ready (not audited) and is for PROTOTYPE/DEMONSTRATION purposes only.
/// - The proposed strategy should pass a strict set of validations like risk assessment, performance metrics, auditing, etc., 
///   before being included in the vault.
contract Vault is ERC4626, Ownable2Step, Pausable, IVault {
    using SafeERC20 for IERC20;
    using PendingLib for PendingUint192;
    using PendingLib for PendingAddress;
    using Math for uint256;
    
    /* STORAGE */

    /// @inheritdoc IVault
    uint96 public fee;
    
    /// @inheritdoc IVault
    address public feeRecipient; 

    /// @inheritdoc IVault
    uint96 public vaultFeeShare;

    /// @inheritdoc IVault
    address public curator;

    /// @inheritdoc IVault
    address public guardian;

    /// @inheritdoc IVault
    uint256 public timelock;
    
    /// @inheritdoc IVault
    PendingAddress public pendingGuardian;

    /// @inheritdoc IVault
    PendingUint192 public pendingTimelock;

    /// @inheritdoc IVault
    mapping (address strategy => PendingUint192) public pendingStrategy;

    /// @inheritdoc IVault
    mapping (address strategy => PendingUint192) public pendingStrategyCap;

    /// @inheritdoc IVault
    uint256 public lostAssets;

    /// @inheritdoc IVault
    uint256 public lastTotalAssets;

    /// @dev List of strategies currently included in the vault.
    address[] internal _strategies;

    /// @inheritdoc IVault
    mapping (address strategy => StrategyConfig) public strategyConfig;

    /* MODIFIERS */

    /// @notice Modifier restrict access only to address with guardian role.
    modifier onlyGuardian() {
        if (msg.sender != guardian) revert ErrorsLib.NotGuardian();
        _;
    }

    /// @notice Modifier restrict access only to address with the curator role.
    modifier onlyCurator() {
        if (msg.sender != curator) revert ErrorsLib.NotCurator();
        _;
    }

    /// @notice Modifier ensures a timelock has elapsed, before allowing the execution of the function.
    /// @param validAt The timestamp at which the change becomes valid.
    modifier afterTimelock(uint256 validAt) {
        if (validAt == 0) revert ErrorsLib.NoPendingChange();
        if (block.timestamp < validAt) revert ErrorsLib.TimelockNotElapsed();
        _;
    }
    
    /* CONSTRUCTOR */

    /// @dev Initializes the contract
    /// @param _asset The address of the underlying asset
    /// @param _name The name of the vault
    /// @param _symbol The symbol of the vault 
    /// @param _vaultFee The vault fee in basis points
    /// @param _feeRecipient The address of the fee recipient
    /// @param _vaultFeeShare The vault fee share in basis points
    /// @param _timelock The timelock duration in seconds
    constructor(
        address _owner,
        address _asset, 
        string memory _name, 
        string memory _symbol,
        uint256 _vaultFee,
        address _feeRecipient,
        uint256 _vaultFeeShare,
        uint256 _timelock
    )
     ERC4626(IERC20(_asset)) 
     ERC20(_name, _symbol)
     Ownable(_owner)
    {
        if (_asset == address(0)) revert ErrorsLib.ZeroAddress();
        if (_feeRecipient == address(0)) revert ErrorsLib.ZeroAddress();
        if (_vaultFee > ConstantsLib.MAX_FEE) revert ErrorsLib.InvalidFeeBPS();
        if (_vaultFeeShare > ConstantsLib.MAX_VAULT_FEE_SHARE_BPS) revert ErrorsLib.InvalidVaultFeeShare();
        if (_timelock > 0) _checkTimelockBounds(_timelock);
        
        _setTimelock(_timelock);
        fee = uint96(_vaultFee);
        feeRecipient = _feeRecipient;
        vaultFeeShare = uint96(_vaultFeeShare);
    }

    /* ERC4626 (PUBLIC) */

    /// @inheritdoc IERC4626
    /// @dev Can be paused by the owner in case of emergency.
    function deposit(uint256 assets, address receiver) public virtual override whenNotPaused returns (uint256) {
        _accrueInterest();
        return super.deposit(assets, receiver);        
    }

    /// @inheritdoc IERC4626
    /// @dev Can be paused by the owner in case of emergency.
    function mint(uint256 shares, address receiver) public virtual override whenNotPaused returns (uint256) {
       _accrueInterest();
       return super.mint(shares, receiver);
    }

    /// @inheritdoc IERC4626
    /// @dev Can be paused by the owner in case of emergency.
    function withdraw(uint256 assets, address receiver, address owner) public virtual override whenNotPaused returns (uint256) {
        _accrueInterest();
        return super.withdraw(assets, receiver, owner);
    }

    /// @inheritdoc IERC4626
    /// @dev Can be paused by the owner in case of emergency.
    function redeem(uint256 shares, address receiver, address owner) public virtual override whenNotPaused returns (uint256) {
        _accrueInterest();
        return super.redeem(shares, receiver, owner);
    }

    /// @inheritdoc ERC4626
    /// @dev Returns the total managed assets including vault's idle funds and strategies balances.
    function totalAssets() public view virtual override returns (uint256) {
        uint256 assetsInVault = IERC20(asset()).balanceOf(address(this));

        uint256 len = _strategies.length;
        for (uint256 i = 0; i < len; ) {
            address strategy = _strategies[i];
            StrategyConfig memory config = strategyConfig[strategy];
            if (config.enabled) {
                assetsInVault += IStrategy(strategy).totalAssets();
            }
            unchecked {
                ++i;
            }
        }

        return assetsInVault;
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
        _accrueInterest();
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
        _accrueInterest();
        uint256 assets = previewMint(shares);
        IERC20Permit(asset()).permit(
            owner, 
            address(this), 
            assets, 
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

    /// @inheritdoc IVault
    function setCurator(address newCurator) external onlyOwner {
        if (newCurator == address(0)) revert ErrorsLib.ZeroAddress();
        if (newCurator == curator) revert ErrorsLib.AlreadySet();

        curator = newCurator;

        emit EventsLib.CuratorUpdated(newCurator);
    }

    /// @inheritdoc IVault
    function submitGuardian(address newGuardian) external onlyOwner {
        if (newGuardian == address(0)) revert ErrorsLib.ZeroAddress();
        if (newGuardian == guardian) revert ErrorsLib.AlreadySet();

        pendingGuardian.update(newGuardian, timelock);

        emit EventsLib.GuardianSubmited(newGuardian);
    }

    /// @inheritdoc IVault
    function submitTimelock(uint256 newTimelock) external onlyOwner {
        if (newTimelock == timelock) revert ErrorsLib.AlreadySet();
        if (pendingTimelock.validAt != 0) revert ErrorsLib.PendingTimelockExists();
        _checkTimelockBounds(newTimelock);

        if (newTimelock >= timelock) {
            // If the new timelock greater than the current timelock, set it immediately
            _setTimelock(newTimelock);
        } else {
            // Safe cast to uint192 due to the of validation in `_setTimelock` function
            pendingTimelock.update(uint192(newTimelock), timelock);
            emit EventsLib.TimelockSubmitted(newTimelock);
        }
    }

     /// @inheritdoc IVault
     function setFee(uint256 newFee) external onlyOwner {
        if (newFee == fee) revert ErrorsLib.AlreadySet();
        if (newFee > ConstantsLib.MAX_FEE) revert ErrorsLib.InvalidFeeBPS();
        // Safe cast to uint96 due to the above `MAX_FEE` validation
        fee = uint96(newFee);
        
        emit EventsLib.FeeUpdated(newFee);
    }

    /// @inheritdoc IVault
    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        if (newFeeRecipient == address(0)) revert ErrorsLib.ZeroAddress();
        if (newFeeRecipient == feeRecipient) revert ErrorsLib.AlreadySet();

        feeRecipient = newFeeRecipient;

        emit EventsLib.FeeRecipientUpdated(newFeeRecipient);
    }

    /// @inheritdoc IVault
    function setVaultFeeShare(uint256 newVaultFeeShare) external onlyOwner {
        if (newVaultFeeShare > ConstantsLib.MAX_VAULT_FEE_SHARE_BPS) revert ErrorsLib.InvalidVaultFeeShare();
        if (newVaultFeeShare == vaultFeeShare) revert ErrorsLib.AlreadySet();
        
        vaultFeeShare = uint96(newVaultFeeShare);
        
        emit EventsLib.VaultFeeShareUpdated(newVaultFeeShare);
    }

    /* ONLY CURATOR FUNCTIONS */

    /// @inheritdoc IVault
    function submitStrategy(address strategy,  uint256 strategyCap) external onlyCurator {
        if (strategy == address(0)) revert ErrorsLib.ZeroAddress();
        if (IStrategy(strategy).vault() != address(this)) revert ErrorsLib.InvalidStrategy();
        if (IStrategy(strategy).asset() != asset()) revert ErrorsLib.InvalidStrategy();
        if (strategyCap == 0) revert ErrorsLib.ZeroStrategyCap();
        if (pendingStrategy[strategy].validAt != 0) revert ErrorsLib.PendingStrategyExists();
        
        pendingStrategy[strategy].update(uint192(strategyCap), timelock);
        
        emit EventsLib.StrategySubmitted(strategy, strategyCap);
    }

    /// @inheritdoc IVault
    function submitStrategyCap(address strategy, uint256 newStrategyCap) external onlyCurator {
        StrategyConfig storage config = strategyConfig[strategy];

        if (!config.enabled) revert ErrorsLib.StrategyNotEnabled();
        if (newStrategyCap == 0) revert ErrorsLib.ZeroStrategyCap();
        if (newStrategyCap == config.cap) revert ErrorsLib.AlreadySet();
        if (pendingStrategyCap[strategy].validAt != 0) revert ErrorsLib.PendingStrategyCapExists();

        if (newStrategyCap < config.cap) {
            _setStrategyCap(strategy, newStrategyCap);
        } else {
            pendingStrategyCap[strategy].update(uint192(newStrategyCap), timelock);

            emit EventsLib.StrategyCapSubmitted(strategy, newStrategyCap);
        }
    }

    /* EXTERNAL FUNCTIONS */

    /// @inheritdoc IVault
    function acceptGuardian() external afterTimelock(pendingGuardian.validAt) {
        _setGuardian(pendingGuardian.value);
    }

    /// @inheritdoc IVault
    function acceptTimelock() external afterTimelock(pendingTimelock.validAt) {
        _setTimelock(pendingTimelock.value);
    }

    /// @inheritdoc IVault
    function acceptStrategy(address strategy) external afterTimelock(pendingStrategy[strategy].validAt) {
        _setStrategy(strategy, pendingStrategy[strategy].value);
    }

    /// @inheritdoc IVault
    function acceptStrategyCap(address strategy) external afterTimelock(pendingStrategy[strategy].validAt) {
        _setStrategyCap(strategy, pendingStrategy[strategy].value);
    }

    /* ONLY GUARDIAN FUNCTIONS */

    /// @inheritdoc IVault
    function revokePendingGuardian() external onlyGuardian {
        if (pendingGuardian.validAt == 0) revert ErrorsLib.NoPendingChange();
        delete pendingGuardian;
        emit EventsLib.PendingGuardianRevoked(msg.sender);
    }

    /// @inheritdoc IVault
    function revokePendingTimelock() external onlyGuardian{
        if (pendingTimelock.validAt == 0) revert ErrorsLib.NoPendingChange();
        delete pendingTimelock;
        emit EventsLib.PendingTimelockRevoked(msg.sender);
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

    /// @notice Checks if the new timelock duration is valid and sets it.
    /// @dev Set `timelock` to `newTimelock` and delete `pendingTimelock`.
    /// @param newTimelock The new timelock duration in seconds.
    function _setTimelock(uint256 newTimelock) internal {
        timelock = newTimelock;
        delete pendingTimelock;
        emit EventsLib.TimelockSet(msg.sender, newTimelock);
    }

    /// @notice Sets the guardian address.
    /// @dev Set `guardian` to `newGuardian` and delete `pendingGuardian`.
    /// @param newGuardian The new guardian address.
    function _setGuardian(address newGuardian) internal {
        guardian = newGuardian;
        delete pendingGuardian;
        emit EventsLib.GuardianUpdated(newGuardian);
    }

    /// @notice Sets the strategy configuration.
    /// @dev Set `strategyConfig[strategy].cap` to `strategyCap` and `strategyConfig[strategy].enabled` to `true`.
    /// After that pushes strategy to the `_strategies` array and deletes the pending strategy.
    /// @param strategy The address of the strategy.
    /// @param strategyCap The cap of the strategy.
    function _setStrategy(address strategy, uint256 strategyCap) internal {
        strategyConfig[strategy].cap = uint184(strategyCap);
        strategyConfig[strategy].enabled = true;
        
        delete pendingStrategy[strategy];
        _strategies.push(strategy);
        
        emit EventsLib.StrategySet(strategy, strategyCap);
    }

    /// @notice Sets the strategy cap.
    /// @dev Set `strategyConfig[strategy].cap` to `newStrategyCap` and delete the pending strategy.
    /// @param strategy The address of the strategy.
    /// @param newStrategyCap The new strategy cap.
    function _setStrategyCap(address strategy, uint256 newStrategyCap) internal {
        strategyConfig[strategy].cap = uint184(newStrategyCap);
        delete pendingStrategyCap[strategy];
        emit EventsLib.StrategyCapUpdated(strategy, newStrategyCap);
    }

    /// @notice Checks if the new timelock duration is valid.
    /// @dev If the new timelock duration is greater than the `MAX_TIMELOCK` or less than the `MIN_TIMELOCK`, the function will revert.
    /// @param newTimelock The new timelock duration in seconds.
    function _checkTimelockBounds(uint256 newTimelock) internal pure {
        if (newTimelock > ConstantsLib.MAX_TIMELOCK) revert ErrorsLib.MaxTimelockExceeded();
        if (newTimelock < ConstantsLib.MIN_TIMELOCK) revert ErrorsLib.MinTimelockNotReached();
    }

    /* FEE MANAGEMENT FUNCTIONS */

    /// @dev Fee split is "vault-first": vault gets `vaultFeeShare` (e.g. 60%) of the performance fee;
    /// the remainder is the strategist pool, distributed among strategy owners in proportion to each
    /// strategy's generated yield. This keeps the vault owner's share fixed regardless of how many strategies exist.
    function _accrueInterest() internal {
        _accrueFeeAndAssets();
    }

    /// @notice Updates the `lastTotalAssets` value.
    /// @dev Set `lastTotalAssets` to `newTotalAssets`.
    /// @param newTotalAssets The new total assets.
    function _updateLastTotalAssets(uint256 newTotalAssets) internal {
        lastTotalAssets = newTotalAssets;
        emit EventsLib.LastTotalAssetsUpdated(newTotalAssets);
    }

    /// @notice Computes performance fee on yield. Vault gets `vaultFeeShare` of the fee, strategists share the rest by yield.
    /// @dev Guarantees the vault owner a fixed share of fees regardless of how many strategies exist.
    /// Workflow:
    /// 1. Update lost assets
    /// 2. Update total assets
    /// 3. Compute performance fee on yield
    /// 4. Get vault fee shares from performance fee and mint respective shares to `feeRecipient`
    /// 5. Compute per-strategy yields, update snapshots, and sum total strategy yield
    /// 6. Get strategies fee shares from performance fee and mint respective shares to strategy owners
    function _accrueFeeAndAssets() internal {
        uint256 currentTotalAssets = totalAssets();
        uint256 newLostAssets = lostAssets;
        
        if (currentTotalAssets < lastTotalAssets - lostAssets) {
            // if there are any lost assets, update the lost assets
            newLostAssets = lastTotalAssets - currentTotalAssets;
        }
        // if no lost assets, then the `lostAssets` remains the same
        lostAssets = newLostAssets;
        
        uint256 newTotalAssets = currentTotalAssets + newLostAssets;
        uint256 totalInterest = newTotalAssets - lastTotalAssets;
        _updateLastTotalAssets(newTotalAssets);

        if (totalInterest != 0 && fee != 0) {
            // Get performance fee in assets --> convert to shares --> get vault fee shares --> mint respective shares to `feeRecipient`
            uint256 feeAssets = totalInterest.mulDiv(fee, ConstantsLib.BPS);
            uint256 feeShares = _convertToShares(feeAssets, Math.Rounding.Floor);
            uint256 vaultFeeShares = feeShares.mulDiv(vaultFeeShare, ConstantsLib.BPS);
            if (vaultFeeShares > 0) {
                _mint(feeRecipient, vaultFeeShares);
            }

            // Compute per-strategy yields, update snapshots, and sum total strategy yield
            uint256 len = _strategies.length;
            uint256[] memory strategyYields = new uint256[](len);
            uint256 totalStrategyYield = 0;

            for (uint256 i = 0; i < len; ) {
                address strategy = _strategies[i];
                StrategyConfig storage config = strategyConfig[strategy];

                if (!config.enabled) {
                    unchecked { ++i; }
                    continue;
                }

                uint256 strategyLastTotalAssets = config.lastTotalAssets;
                uint256 strategyCurrentTotalAssets = IStrategy(strategy).totalAssets();
                config.lastTotalAssets = strategyCurrentTotalAssets;
                config.lastAccrualTimestamp = uint64(block.timestamp);

                if (strategyCurrentTotalAssets > strategyLastTotalAssets) {
                    uint256 yield = strategyCurrentTotalAssets - strategyLastTotalAssets;
                    strategyYields[i] = yield;
                    totalStrategyYield += yield;
                }

                unchecked { ++i; }
            }

            // `strategiesFeeShares` = performance fee shares left after vault fee. 
            // E.g vault fee share is 60%, then strategies pool share is 40%
            uint256 strategiesFeeShares = feeShares - vaultFeeShares;
            if (strategiesFeeShares > 0 && totalStrategyYield > 0) {
                for (uint256 i = 0; i < len; ) {
                    if (strategyYields[i] == 0) {
                        unchecked { ++i; }
                        continue;
                    }
                    uint256 strategyOwnerShares = strategiesFeeShares.mulDiv(strategyYields[i], totalStrategyYield);
                    if (strategyOwnerShares > 0) {
                        address owner = IStrategy(_strategies[i]).strategyOwner();
                        _mint(owner, strategyOwnerShares);
                    }
                    unchecked { ++i; }
                }
            }
    
            emit EventsLib.LastTotalAssetsUpdated(newTotalAssets);
        }
    }

    /* ERC4626 (INTERNAL) */

    /// @inheritdoc ERC4626
    /// @dev Returns the number of decimals to add to the underlying asset's decimals.
    function _decimalsOffset() internal view virtual override returns (uint8) {
        return 9;
    }

    
}