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
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

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
    using SafeCast for uint256;
    
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
    /// Used as strategies registry.
    /// IMPORTANT: Disabled strategies are not removed from the array. The max strategies amount is limited to `MAX_QUEUE_LENGTH`.
    address[] internal _strategies;

    /// @dev List of strategies currently in the supply list.
    /// Used for assets allocation routing.
    address[] internal _supplyQueue;

    /// @dev List of strategies currently in the withdraw list.
    /// Used for assets allocation routing.
    address[] internal _withdrawQueue;

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
    function maxDeposit(address) public view override returns (uint256 maxAssets) {
        maxAssets = _maxDeposit();
    }

    /// @inheritdoc IERC4626
    /// @dev Convert suppliable assets to shares with fee-aware totals.
    function maxMint(address) public view override returns (uint256 maxShares) {
        uint256 suppliable = _maxDeposit();

        (uint256 newTotalAssets,,,,, uint256 feeShares) = _calculateFeeAndTotals();
        uint256 newTotalSupply = totalSupply() + feeShares;

        maxShares = _convertToSharesWithTotals(suppliable, newTotalSupply, newTotalAssets, Math.Rounding.Floor);
    }

    /// @inheritdoc IERC4626
    function maxWithdraw(address owner) public view override returns (uint256 maxAssets) {
        (uint256 assets,,) = _maxWithdraw(owner);
        maxAssets = assets;
    }

    /// @inheritdoc IERC4626
    function maxRedeem(address owner) public view override returns (uint256 maxShares) {
        (uint256 assets, uint256 newTotalSupply, uint256 newTotalAssets) = _maxWithdraw(owner);
        if (assets == 0) return 0;

        maxShares = _convertToSharesWithTotals(assets, newTotalSupply, newTotalAssets, Math.Rounding.Floor);
    }

    /// @inheritdoc IERC4626
    /// @dev Can be paused by the owner in case of emergency.
    /// Instead of calling `previewDeposit()` with expensive `totalAssets()` function inside, the function calculates 
    /// the current total assets inside `_accrueInterest()` function and use it to calculate the shares.
    function deposit(uint256 assets, address receiver) public virtual override whenNotPaused returns (uint256 shares) {
        _accrueInterest();

        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);

        shares = _convertToSharesWithTotals(assets, totalSupply(), lastTotalAssets, Math.Rounding.Floor);
        _deposit(msg.sender, receiver, assets, shares);
    }

    /// @inheritdoc IERC4626
    /// @dev Can be paused by the owner in case of emergency.
    /// Instead of calling `previewMint()` with expensive `totalAssets()` function inside, the function calculates 
    /// the current total assets inside `_accrueInterest()` function and use it to calculate the assets.
    function mint(uint256 shares, address receiver) public virtual override whenNotPaused returns (uint256 assets) {
       _accrueInterest();

       uint256 maxShares = maxMint(receiver);
       if (shares > maxShares) revert ERC4626ExceededMaxMint(receiver, shares, maxShares);

       assets = _convertToAssetsWithTotals(shares, totalSupply(), lastTotalAssets, Math.Rounding.Ceil);
       _deposit(msg.sender, receiver, assets, shares);
    }

    /// @inheritdoc IERC4626
    /// @dev Can be paused by the owner in case of emergency.
    /// Instead of calling `previewWithdraw()` with expensive `totalAssets()` function inside, the function calculates 
    /// the current total assets inside `_accrueInterest()` function and use it to calculate the shares.
    function withdraw(uint256 assets, address receiver, address owner) public virtual override whenNotPaused returns (uint256 shares) {
        _accrueInterest();

        uint256 maxAssets = maxWithdraw(owner);
        if (assets > maxAssets) revert ERC4626ExceededMaxWithdraw(owner, assets, maxAssets);

        shares = _convertToSharesWithTotals(assets, totalSupply(), lastTotalAssets, Math.Rounding.Ceil);
        _withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /// @inheritdoc IERC4626
    /// @dev Can be paused by the owner in case of emergency.
    /// Instead of calling `previewRedeem()` with expensive `totalAssets()` function inside, the function calculates 
    /// the current total assets inside `_accrueInterest()` function and use it to calculate the assets.
    function redeem(uint256 shares, address receiver, address owner) public virtual override whenNotPaused returns (uint256 assets) {
        _accrueInterest();

        uint256 maxShares = maxRedeem(owner);
        if (shares > maxShares) revert ERC4626ExceededMaxRedeem(owner, shares, maxShares);

        assets = _convertToAssetsWithTotals(shares, totalSupply(), lastTotalAssets, Math.Rounding.Floor);
        _withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /// @inheritdoc ERC4626
    /// @dev Returns the total managed assets including vault's idle funds and strategies balances + lost assets.
    function totalAssets() public view virtual override returns (uint256) {
        (uint256 newTotalAssets, , , , , ) = _calculateFeeAndTotals();
        return newTotalAssets;
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
    ) public virtual whenNotPaused returns (uint256 shares) {
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
        
        uint256 maxAssets = maxDeposit(receiver);
        if (assets > maxAssets) revert ERC4626ExceededMaxDeposit(receiver, assets, maxAssets);
    
        shares = _convertToSharesWithTotals(assets, totalSupply(), lastTotalAssets, Math.Rounding.Floor);
        _deposit(owner, receiver, assets, shares);
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
    ) public virtual whenNotPaused returns (uint256 assets) {
        if (shares == 0) revert ErrorsLib.ZeroSharesInAmount();
        
        _accrueInterest();
        
        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) revert ERC4626ExceededMaxMint(receiver, shares, maxShares);

        assets = _convertToAssetsWithTotals(shares, totalSupply(), lastTotalAssets, Math.Rounding.Ceil);

        IERC20Permit(asset()).permit(
            owner, 
            address(this), 
            assets, 
            deadline, 
            permitV, 
            permitR, 
            permitS
        );

        _deposit(owner, receiver, assets, shares);
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
        if (pendingGuardian.validAt != 0) revert ErrorsLib.PendingGuardianExist();

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
            // Safe cast to uint192 due to overflows prevention in `_setTimelock` function
            pendingTimelock.update(uint192(newTimelock), timelock);
            emit EventsLib.TimelockSubmitted(newTimelock);
        }
    }

     /// @inheritdoc IVault
     function setFee(uint256 newFee) external onlyOwner {
        if (newFee == fee) revert ErrorsLib.AlreadySet();
        if (newFee > ConstantsLib.MAX_FEE) revert ErrorsLib.InvalidFeeBPS();
        
        // Accrue interest and fee using the old fee before setting the new fee
        _accrueInterest();

        // Safe cast to uint96 due to the above `MAX_FEE` validation
        fee = uint96(newFee);
        
        emit EventsLib.FeeUpdated(newFee);
    }

    /// @inheritdoc IVault
    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        if (newFeeRecipient == address(0)) revert ErrorsLib.ZeroAddress();
        if (newFeeRecipient == feeRecipient) revert ErrorsLib.AlreadySet();
        
        // Accrue interest and fee for the previous fee recipient before setting the new fee recipient
        _accrueInterest();
        
        feeRecipient = newFeeRecipient;

        emit EventsLib.FeeRecipientUpdated(newFeeRecipient);
    }

    /// @inheritdoc IVault
    function setVaultFeeShare(uint256 newVaultFeeShare) external onlyOwner {
        if (newVaultFeeShare > ConstantsLib.MAX_VAULT_FEE_SHARE_BPS) revert ErrorsLib.InvalidVaultFeeShare();
        if (newVaultFeeShare == vaultFeeShare) revert ErrorsLib.AlreadySet();
        
        // Accrue interest and fee for the previous vault fee share before setting the new vault fee share
        _accrueInterest();

        vaultFeeShare = uint96(newVaultFeeShare);
        
        emit EventsLib.VaultFeeShareUpdated(newVaultFeeShare);
    }

    /* ONLY CURATOR FUNCTIONS */

    /// @inheritdoc IVault
    function submitStrategy(address strategy,  uint256 strategyCap) external onlyCurator {
        StrategyConfig storage config = strategyConfig[strategy];

        if (strategy == address(0)) revert ErrorsLib.ZeroAddress();
        if (_strategies.length == ConstantsLib.MAX_QUEUE_LENGTH) revert ErrorsLib.MaxStrategiesReached();
        // Checking strategy `enabled` is not enough because the strategy can be disabled and validation will read it as non existent strategy.
        // And `lastAccrualTimestamp` is used to avoid submitting the same strategy again.
        if (config.enabled || config.lastAccrualTimestamp != 0) revert ErrorsLib.StrategyAlreadyExists();
        if (IStrategy(strategy).vault() != address(this)) revert ErrorsLib.InvalidStrategy();
        if (IStrategy(strategy).asset() != asset()) revert ErrorsLib.InvalidStrategy();
        if (strategyCap == 0) revert ErrorsLib.ZeroStrategyCap();
        if (pendingStrategy[strategy].validAt != 0) revert ErrorsLib.PendingStrategyExists();
        
        pendingStrategy[strategy].update(strategyCap.toUint184(), timelock);
        
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
            _setStrategyCap(strategy, newStrategyCap.toUint184());
        } else {
            pendingStrategyCap[strategy].update(newStrategyCap.toUint184(), timelock);

            emit EventsLib.StrategyCapSubmitted(strategy, newStrategyCap);
        }
    }

    /// @inheritdoc IVault
    function setSupplyQueue(address[] calldata newSupplyQueue) external onlyCurator {
        _checkQueue(newSupplyQueue);
        _supplyQueue = newSupplyQueue;
        emit EventsLib.SetSupplyQueue(newSupplyQueue);
    }

    /// @inheritdoc IVault
    function setWithdrawQueue(address[] calldata newWithdrawQueue) external onlyCurator {
        _checkQueue(newWithdrawQueue);
        _withdrawQueue = newWithdrawQueue;
        emit EventsLib.SetWithdrawQueue(newWithdrawQueue);
    }

    /// @inheritdoc IVault
    function disableStrategy(address strategy) external onlyCurator {
        StrategyConfig storage config = strategyConfig[strategy];
        if (!config.enabled) revert ErrorsLib.StrategyNotEnabled();

        _accrueInterest();

        config.cap = 0;
        config.enabled = false;
        config.lastTotalAssets = 0;

        delete pendingStrategy[strategy];
        delete pendingStrategyCap[strategy];

        _removeFromQueue(strategy, _supplyQueue);
        _removeFromQueue(strategy, _withdrawQueue);

        // Withdraw all remaining assets from the strategy
        uint256 strategyAssets = IStrategy(strategy).totalAssets();
        if (strategyAssets > 0) {
            uint256 withdrawnAssets = IStrategy(strategy).withdraw(strategyAssets, address(this));
            if (withdrawnAssets != strategyAssets) {
                lostAssets += strategyAssets - withdrawnAssets;
            }
        }

        // Update the global snapshot to reflect the new total assets balance.
        _updateLastTotalAssets(totalAssets());

        emit EventsLib.StrategyDisabled(strategy);
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
        _setStrategy(strategy, uint184(pendingStrategy[strategy].value));
    }

    /// @inheritdoc IVault
    function acceptStrategyCap(address strategy) external afterTimelock(pendingStrategyCap[strategy].validAt) {
        _setStrategyCap(strategy, uint184(pendingStrategyCap[strategy].value));
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

    /// @inheritdoc IVault
    function revokePendingStrategy(address strategy) external onlyGuardian {
        if (pendingStrategy[strategy].validAt == 0) revert ErrorsLib.NoPendingChange();
        delete pendingStrategy[strategy];
        emit EventsLib.PendingStrategyRevoked(msg.sender);
    }

    /// @inheritdoc IVault
    function revokePendingStrategyCap(address strategy) external onlyGuardian {
        if (pendingStrategyCap[strategy].validAt == 0) revert ErrorsLib.NoPendingChange();
        delete pendingStrategyCap[strategy];
        emit EventsLib.PendingStrategyCapRevoked(msg.sender);
    }

    /* INTERNAL FUNCTIONS */

    /// @notice Sets the timelock duration.
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
    /// @dev Initialize the strategy configuration and push it to the `_strategies` array.
    /// @param strategy The address of the strategy.
    /// @param strategyCap The cap of the strategy.
    function _setStrategy(address strategy, uint184 strategyCap) internal {
        StrategyConfig storage config = strategyConfig[strategy];

        config.cap = strategyCap;
        config.enabled = true;
        // Initialize strategy snapshots so first accrual doesn't treat principal as yield.
        config.lastTotalAssets = IStrategy(strategy).totalAssets();
        config.lastAccrualTimestamp = uint64(block.timestamp);
        
        delete pendingStrategy[strategy];
        // Duplicates avoided during the duplicate check in `submitStrategy` function
        _strategies.push(strategy); 
        
        emit EventsLib.StrategySet(strategy, strategyCap);
    }

    /// @notice Sets the strategy cap.
    /// @dev Set `strategyConfig[strategy].cap` to `newStrategyCap` and delete the pending strategy.
    /// @param strategy The address of the strategy.
    /// @param newStrategyCap The new strategy cap.
    function _setStrategyCap(address strategy, uint184 newStrategyCap) internal {
        strategyConfig[strategy].cap = newStrategyCap;
        delete pendingStrategyCap[strategy];
        emit EventsLib.StrategyCapUpdated(strategy, newStrategyCap);
    }

    /// @notice Removes a strategy from the supply/withdraw queue using swap-and-pop.
    /// @dev No-op if the strategy is not in the queue.
    /// @param strategy The address of the strategy to remove.
    /// @param queue The queue to remove the strategy from.
    function _removeFromQueue(address strategy, address[] storage queue) internal {
        uint256 len = queue.length;
        for (uint256 i; i < len;) {
            if (queue[i] == strategy) {
                queue[i] = queue[len - 1];
                queue.pop();
                return;
            }
            unchecked { ++i; }
        }
    }

    /// @notice Checks if the new timelock duration is valid.
    /// @dev If the new timelock duration is greater than the `MAX_TIMELOCK` or less than the `MIN_TIMELOCK`, the function will revert.
    /// @param newTimelock The new timelock duration in seconds.
    function _checkTimelockBounds(uint256 newTimelock) internal pure {
        if (newTimelock > ConstantsLib.MAX_TIMELOCK) revert ErrorsLib.MaxTimelockExceeded();
        if (newTimelock < ConstantsLib.MIN_TIMELOCK) revert ErrorsLib.MinTimelockNotReached();
    }

    /// @notice Checks if the new queue (can be supply/withdraw queue) is valid.
    /// @dev Function iterates over the provided `newQueue` parameter and checks if the queue is valid.
    /// @param newQueue The new queue to check.
    function _checkQueue(address[] calldata newQueue) internal view {
        uint256 length = newQueue.length;
        if (length > ConstantsLib.MAX_QUEUE_LENGTH) revert ErrorsLib.MaxQueueLengthExceeded();

        for (uint256 i = 0; i < length;) {
            address strategy = newQueue[i];
            if (strategy == address(0)) revert ErrorsLib.ZeroAddress();
            if (!strategyConfig[strategy].enabled) revert ErrorsLib.StrategyNotEnabled();

            for (uint256 j = i + 1; j < length; ) {
                if (newQueue[j] == strategy) revert ErrorsLib.StrategyDuplicate();
                unchecked { ++j; }
            }
            unchecked { ++i; }
        }
    }

    /* LIQUIDITY ALLOCATION */
    
    /// @notice Supplies `assets` to the appropriate strategy using the supply queue.
    /// @dev Routes the assets to the appropriate strategy using the supply queue `_supplyQueue` 
    /// and updates the strategies `lastTotalAssets` value.
    /// @param assets The amount of assets to supply.
    function _supplyToStrategy(uint256 assets) internal {
        uint256 length = _supplyQueue.length;

        for (uint256 i = 0; i < length && assets > 0; ) {
            address strategy = _supplyQueue[i];
            StrategyConfig storage config = strategyConfig[strategy];
            
            if (!config.enabled) { unchecked {++i;} continue; }

            uint256 strategyAssets = IStrategy(strategy).totalAssets();
            uint256 remainingCap = config.cap - strategyAssets;
            
            // If the remainingCap will underflow - result to 0, then the strategy cap is reached, and we skip the strategy deposit.
            if (remainingCap > 0) {
                uint256 toSupply = assets > remainingCap ? remainingCap : assets;
                
                try IStrategy(strategy).deposit(toSupply) {
                    config.lastTotalAssets = IStrategy(strategy).totalAssets(); // TODO: potential place for improvement. Calling each strategy totalAssets() can be expensive.
                    assets -= toSupply;
                } catch {}
            }
            unchecked {++i;}
        }
        // If there are any remaining assets, it means that all the strategy caps are reached.
        if (assets != 0) revert ErrorsLib.AllCapsReached();
    }

    /// @notice Withdraws `assets` from the appropriate strategy using the withdraw queue.
    /// @dev Fetches assets from the strategies via `_withrawQueue` and updates the strategies `lastTotalAssets` value.
    /// @param assets The amount of assets to withdraw.
    function _withdrawFromStrategy(uint256 assets) internal {
        uint256 length = _withdrawQueue.length;

        for (uint256 i = 0; i < length && assets > 0; ) {
            address strategy = _withdrawQueue[i];
            StrategyConfig storage config = strategyConfig[strategy];

            if (!config.enabled) { unchecked {++i;} continue; }

            uint256 strategyAssets = IStrategy(strategy).totalAssets();
            if (strategyAssets == 0) { unchecked {++i;} continue; }

            uint256 toWithdraw = assets > strategyAssets ? strategyAssets : assets;
            try IStrategy(strategy).withdraw(toWithdraw, address(this)) returns (uint256 withdrawn) {
                config.lastTotalAssets = IStrategy(strategy).totalAssets();
                assets -= withdrawn;
            } catch {}

            unchecked {++i;}
        }

        // If there are any remaining assets, it means that there is not enough liquidity in strategies.
        if (assets != 0) revert ErrorsLib.NotEnoughLiquidity();
    }

    /// @dev Simulates the withdraw path (idle first, then `_withdrawQueue` in order) and returns
    /// how many of the requested `assets` cannot be covered — the liquidity gap.
    /// Returns 0 when the full amount is coverable.
    function _withdrawalLiquidityGap(uint256 assets) internal view returns (uint256 remaining) {
        if (assets == 0) return 0;

        remaining = assets;

        uint256 idle = IERC20(asset()).balanceOf(address(this));
        remaining -= idle > remaining ? remaining : idle;

        uint256 length = _withdrawQueue.length;
        for (uint256 i = 0; i < length && remaining > 0; ) {
            address strategy = _withdrawQueue[i];

            if (!strategyConfig[strategy].enabled) { unchecked { ++i; } continue; }

            uint256 available = IStrategy(strategy).totalAssets();
            remaining -= available > remaining ? remaining : available;

            unchecked { ++i; }
        }
    }

    /* ERC4626 (INTERNAL) */

    /// @dev Returns the maximum depositable assets based on remaining supply queue cap headroom.
    function _maxDeposit() internal view returns (uint256 suppliable) {
        uint256 length = _supplyQueue.length;
        
        for (uint256 i = 0; i < length; ) {
            address strategy = _supplyQueue[i];
            StrategyConfig memory config = strategyConfig[strategy];

            if (!config.enabled || config.cap == 0) { unchecked {++i;} continue; }

            uint256 strategyAssets = IStrategy(strategy).totalAssets();
            
            // yield can push strategyAssets above cap; treat as zero headroom (no underflow).
            if (strategyAssets >= config.cap) { unchecked {++i;} continue; }

            unchecked {
                suppliable += config.cap - strategyAssets;
                ++i;
            }
        }
    }

    /// @dev Returns the maximum withdrawable assets for `owner`, capped by real liquidity along the withdraw path.
    /// Also returns the fee-preview totals so `maxRedeem` can reuse them without a second `_calculateFeeAndTotals` call.
    function _maxWithdraw(address owner) internal view returns (uint256 assets, uint256 newTotalSupply, uint256 newTotalAssets) {
        uint256 feeShares;
        (newTotalAssets, , , , , feeShares) = _calculateFeeAndTotals();
        newTotalSupply = totalSupply() + feeShares;

        assets = _convertToAssetsWithTotals(balanceOf(owner), newTotalSupply, newTotalAssets, Math.Rounding.Floor);

        uint256 liquidityGap = _withdrawalLiquidityGap(assets);
        assets -= liquidityGap;
    }

    /// @inheritdoc ERC4626
    /// @dev Used in `deposit`, `depositWithPermit`, `mint`, `mintWithPermit` functions to deposit underlying asset to vault strategies.
    /// Routes the assets to the appropriate strategy using the supply queue and updates the `lastTotalAssets` value.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        super._deposit(caller, receiver, assets, shares);
        _supplyToStrategy(assets);
        _updateLastTotalAssets(lastTotalAssets + assets);
    }

    /// @inheritdoc ERC4626
    /// @dev Used in `withdraw`, `redeem` functions to withdraw underlying asset from vault strategies.
    /// Routes the assets to the appropriate strategy using the withdraw queue and updates the `lastTotalAssets` value.
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares) internal override {
        _updateLastTotalAssets(lastTotalAssets - assets);

        // Take the balance of the vault to see if there are any idle assets to withdraw. If there is not enough idle assets,
        // then withdraw the remaining assets from the strategies.
        uint256 idle = IERC20(asset()).balanceOf(address(this));
        if (idle < assets) {
            _withdrawFromStrategy(assets - idle);
        }

        super._withdraw(caller, receiver, owner, assets, shares);
    }

    /// @inheritdoc ERC4626
    /// @dev Returns the number of decimals to add to the underlying asset's decimals.
    function _decimalsOffset() internal view virtual override returns (uint8) {
        return 9;
    }

    function _convertToSharesWithTotals(
        uint256 assets, 
        uint256 newTotalSupply, 
        uint256 newTotalAssets, 
        Math.Rounding rounding
    ) internal view returns (uint256) {
        return assets.mulDiv(newTotalSupply + 10 ** _decimalsOffset(), newTotalAssets + 1, rounding);
    }

    function _convertToAssetsWithTotals(
        uint256 shares,
        uint256 newTotalSupply,
        uint256 newTotalAssets,
        Math.Rounding rounding
    ) internal view returns (uint256) {
        return shares.mulDiv(newTotalAssets + 1, newTotalSupply + 10 ** _decimalsOffset(), rounding);
    }

    /* FEE MANAGEMENT FUNCTIONS */

    /// @notice Updates the `lastTotalAssets` value.
    /// @dev Set `lastTotalAssets` to `newTotalAssets`.
    /// @param newTotalAssets The new total assets.
    function _updateLastTotalAssets(uint256 newTotalAssets) internal {
        lastTotalAssets = newTotalAssets;
        emit EventsLib.LastTotalAssetsUpdated(newTotalAssets);
    }

    /// @notice Computes performance fee on yield. Vault gets `vaultFeeShare` of the fee, strategists share the rest by yield.
    /// Updates new `lastTotalAssets` value, `lostAssets` value, and updates each strategy's `lastTotalAssets` and `lastAccrualTimestamp` values.
    /// @dev Guarantees the vault owner a fixed share of fees regardless of how many strategies exist.
    /// 
    /// Workflow:
    /// 1. Update each strategy's `lastTotalAssets` and `lastAccrualTimestamp` values.
    /// 2. Update `lostAssets` value if any, and update `lastTotalAssets` value.
    /// 3. Get vault fee share `vaultFeeShare` from performance fee `feeShares` value and mint respective shares to `feeRecipient`
    /// 4. Get strategies fee shares `strategiesFeeShares` from performance fee `feeShares` and mint respective shares to strategy owners
    /// based on their yield `strategyYields` and total yield `totalStrategyYield`.
    function _accrueInterest() internal {
        (
            uint256 newTotalAssets,
            uint256 newLostAssets,
            uint256 totalStrategyYield,
            uint256[] memory strategyYields,
            uint256[] memory strategyCurrentAssets,
            uint256 feeShares
        ) = _calculateFeeAndTotals();
    
        // Write strategy snapshots
        uint256 length = _strategies.length;
        for (uint256 i = 0; i < length; ) {
            address strategy = _strategies[i];
            StrategyConfig storage config = strategyConfig[strategy];
    
            if (config.enabled) {
                config.lastTotalAssets = strategyCurrentAssets[i];
                config.lastAccrualTimestamp = uint64(block.timestamp);
            }
    
            unchecked { ++i; }
        }
    
        // Write global state
        if (newLostAssets != lostAssets) {
            lostAssets = newLostAssets;
        }
        _updateLastTotalAssets(newTotalAssets);
    
        // Mint fee shares
        if (feeShares > 0) {
            uint256 vaultFeeShares = feeShares.mulDiv(vaultFeeShare, ConstantsLib.BPS);
            if (vaultFeeShares > 0) {
                _mint(feeRecipient, vaultFeeShares);
            }
    
            uint256 strategiesFeeShares = feeShares - vaultFeeShares;
            if (strategiesFeeShares > 0 && totalStrategyYield > 0) {
                for (uint256 i = 0; i < length; ) {
                    if (strategyYields[i] == 0) { unchecked { ++i; } continue; }
    
                    uint256 strategyOwnerShares = strategiesFeeShares.mulDiv(strategyYields[i], totalStrategyYield);
                    if (strategyOwnerShares > 0) {
                        _mint(IStrategy(_strategies[i]).strategyOwner(), strategyOwnerShares);
                    }
    
                    unchecked { ++i; }
                }
            }
        }
    }   

    /// @notice Calculates the interest, lost assets, total assets, strategy yields and fee shares.
    /// @dev Function calculates the above values and returns them in a tuple.
    ///
    /// @return newTotalAssets The current total assets including idle vault balance and strategies balances + lost assets.
    /// @return newLostAssets The new lost assets.
    /// @return totalStrategyYield The total yield of all strategies.
    /// @return strategyYields The separate yield of each strategy.
    /// @return strategyCurrentAssets The current total assets of each strategy.
    /// @return feeShares The fee shares to be minted to `feeRecipient` and strategy owners.
    function _calculateFeeAndTotals() internal view returns (
        uint256 newTotalAssets, 
        uint256 newLostAssets, 
        uint256 totalStrategyYield,
        uint256[] memory strategyYields,
        uint256[] memory strategyCurrentAssets,
        uint256 feeShares
    ) {
        // Calculate the current total assets including idle vault balance and strategies balances.
        uint256 currentTotalAssets = IERC20(asset()).balanceOf(address(this));
        uint256 length = _strategies.length;
        strategyYields = new uint256[](length);

        for (uint256 i = 0; i < length; ) {
            address strategy = _strategies[i];
            StrategyConfig memory config = strategyConfig[strategy];

            if (!config.enabled) { unchecked { ++i; } continue; }

            uint256 currentStrategyAssets = IStrategy(strategy).totalAssets();
            // This array is passed t `accrueInterest()` and avoid calling `totalAssets()` function for each strategy twice.
            strategyCurrentAssets[i] = currentStrategyAssets;
            currentTotalAssets += currentStrategyAssets;

            if (currentStrategyAssets > config.lastTotalAssets) {
                uint256 yield = currentStrategyAssets - config.lastTotalAssets;
                strategyYields[i] = yield;
                totalStrategyYield += yield;
            }

            unchecked { ++i; }
        }

        uint256 lastLostAssets = lostAssets;
        newLostAssets = lastLostAssets;

        if (currentTotalAssets < lastTotalAssets - lastLostAssets) {
            newLostAssets = lastTotalAssets - currentTotalAssets;
        }

        newTotalAssets = currentTotalAssets + newLostAssets;
        uint256 totalInterest = newTotalAssets - lastTotalAssets;

        if (totalInterest != 0 && fee != 0) {
            uint256 feeAssets = totalInterest.mulDiv(fee, ConstantsLib.BPS);
            feeShares = _convertToSharesWithTotals(feeAssets, totalSupply(), newTotalAssets - feeAssets, Math.Rounding.Floor);
        }
    }
}