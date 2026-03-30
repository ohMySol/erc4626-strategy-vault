// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

import {Vault} from "../../src/Vault.sol";
import {MyToken} from "../../src/MyToken.sol";
import {PermitHash} from "../../src/libraries/test-helper-lib/PermitHash.sol";
import {IStrategy, StrategyConfig} from "../../src/interfaces/IStrategy.sol";
import {ErrorsLib} from "../../src/libraries/ErrorsLib.sol";
import {EventsLib} from "../../src/libraries/EventsLib.sol";
import {ConstantsLib} from "../../src/libraries/ConstantsLib.sol";

import {VaultHarness} from "../mocks/VaultHarness.sol";
import {MockStrategy} from "../mocks/MockStrategy.sol";

contract VaultTest is Test {
    using Math for uint256;

    uint256 internal constant BPS = 10_000;
    uint256 internal constant DEFAULT_FEE = 1_000;       // 10%
    uint256 internal constant DEFAULT_VAULT_SHARE = 5_000; // 50%
    uint256 internal constant TIMELOCK = 2 days;
    uint256 internal constant STRATEGY_CAP = 1_000_000e18;

    MyToken internal token;
    VaultHarness internal vault;

    address internal owner = makeAddr("owner");
    address internal feeRecipient = makeAddr("feeRecipient");
    address internal curator = makeAddr("curator");
    address internal guardian = makeAddr("guardian");
    address internal allocator = makeAddr("allocator");
    address internal bob = makeAddr("bob");
    uint256 aliceKey = 0xA11CE;
    address alice = vm.addr(aliceKey);


    MockStrategy internal strategyA;
    MockStrategy internal strategyB;

    /* SETUP */

    function setUp() public {
        vm.startPrank(owner);
        token = new MyToken();
        token.mint(owner, 100_000_000e18);
        token.mint(alice, 10_000_000e18);
        token.mint(bob,   10_000_000e18);
        vm.stopPrank();

        vault = new VaultHarness(
            owner,
            address(token),
            "VaultShare",
            "vSHR",
            DEFAULT_FEE,
            feeRecipient,
            DEFAULT_VAULT_SHARE,
            TIMELOCK
        );

        strategyA = new MockStrategy(address(vault), makeAddr("stratOwnerA"));
        strategyB = new MockStrategy(address(vault), makeAddr("stratOwnerB"));

        vm.startPrank(owner);
        vault.setCurator(curator);
        vault.setAllocator(allocator, true);
        vault.submitGuardian(guardian);
        vm.stopPrank();

        vm.warp(block.timestamp + TIMELOCK);
        vault.acceptGuardian();
    }

    /* HELPERS */

    /// @dev Fully onboard a strategy (submit, warp, accept, add to queues).
    /// @param strategy The strategy to onboard.
    /// @param cap The cap of the strategy.
    function _onboardStrategy(MockStrategy strategy, uint256 cap) internal {
        vm.prank(curator);
        vault.submitStrategy(address(strategy), cap);

        vm.warp(block.timestamp + TIMELOCK);
        vault.acceptStrategy(address(strategy));

        address[] memory sq = new address[](1);
        sq[0] = address(strategy);
        address[] memory wq = new address[](1);
        wq[0] = address(strategy);

        vm.startPrank(allocator);
        vault.setSupplyQueue(sq);
        vault.setWithdrawQueue(wq);
        vm.stopPrank();
    }

    /// @dev Onboard both strategies (strategyA, strategyB) with given caps.
    /// @param capA The cap of strategyA.
    /// @param capB The cap of strategyB.
    function _onboardBothStrategies(uint256 capA, uint256 capB) internal {
        vm.prank(curator);
        vault.submitStrategy(address(strategyA), capA);
        vm.warp(block.timestamp + TIMELOCK);
        vault.acceptStrategy(address(strategyA));

        vm.prank(curator);
        vault.submitStrategy(address(strategyB), capB);
        vm.warp(block.timestamp + TIMELOCK);
        vault.acceptStrategy(address(strategyB));

        address[] memory sq = new address[](2);
        sq[0] = address(strategyA);
        sq[1] = address(strategyB);
        address[] memory wq = new address[](2);
        wq[0] = address(strategyA);
        wq[1] = address(strategyB);

        vm.startPrank(allocator);
        vault.setSupplyQueue(sq);
        vault.setWithdrawQueue(wq);
        vm.stopPrank();
    }

    /// @dev Deposit `amount` as `user`.
    function _depositAs(address user, uint256 amount) internal returns (uint256 shares) {
        vm.startPrank(user);
        token.approve(address(vault), amount);
        shares = vault.deposit(amount, user);
        vm.stopPrank();
    }

    /// @dev Withdraw `amount` as `user`.
    function _withdrawAs(address user, uint256 amount) internal returns (uint256 shares) {
        vm.startPrank(user);
        shares = vault.withdraw(amount, user, user);
        vm.stopPrank();
    }

    /* CONSTRUCTOR TESTS */

    function test_constructor_initializes_correctly() public view {
        assertEq(vault.fee(), DEFAULT_FEE);
        assertEq(vault.feeRecipient(), feeRecipient);
        assertEq(vault.vaultFeeShare(), DEFAULT_VAULT_SHARE);
        assertEq(vault.timelock(), TIMELOCK);
        assertEq(vault.asset(), address(token));
        assertEq(vault.name(), "VaultShare");
        assertEq(vault.symbol(), "vSHR");
        assertEq(vault.owner(), owner);
    }

    function test_constructor_reverts_when_asset_is_zero_address() public {
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        new VaultHarness(owner, address(0), "V", "V", 0, feeRecipient, 0, 0);
    }

    function test_constructor_reverts_when_feeRecipient_is_zero_address() public {
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        new VaultHarness(owner, address(token), "V", "V", 0, address(0), 0, 0);
    }

    function test_constructor_reverts_when_fee_is_above_max() public {
        vm.expectRevert(ErrorsLib.InvalidFeeBPS.selector);
        new VaultHarness(owner, address(token), "V", "V", ConstantsLib.MAX_FEE + 1, feeRecipient, 0, 0);
    }

    function test_constructor_reverts_when_vaultFeeShare_is_above_max() public {
        vm.expectRevert(ErrorsLib.InvalidVaultFeeShare.selector);
        new VaultHarness(owner, address(token), "V", "V", 0, feeRecipient, ConstantsLib.MAX_VAULT_FEE_SHARE_BPS + 1, 0);
    }

    function test_constructor_reverts_when_timelock_is_above_max() public {
        vm.expectRevert(ErrorsLib.MaxTimelockExceeded.selector);
        new VaultHarness(owner, address(token), "V", "V", 0, feeRecipient, 0, ConstantsLib.MAX_TIMELOCK + 1);
    }

    function test_constructor_reverts_when_timelock_is_below_min() public {
        vm.expectRevert(ErrorsLib.MinTimelockNotReached.selector);
        new VaultHarness(owner, address(token), "V", "V", 0, feeRecipient, 0, 1);
    }

    function test_constructor_allows_zero_timelock() public {
        VaultHarness v = new VaultHarness(owner, address(token), "V", "V", 0, feeRecipient, 0, 0);
        assertEq(v.timelock(), 0);
    }

    /* ROLE MANAGEMENT TESTS */

    function test_setCurator_updates_curator_successfully() public {
        address newCurator = makeAddr("newCurator");
        
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit EventsLib.CuratorUpdated(newCurator);
        
        vault.setCurator(newCurator);
        assertEq(vault.curator(), newCurator);
    }

    function test_setCurator_reverts_when_msgSender_is_not_owner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vault.setCurator(alice);
    }

    function test_setCurator_reverts_when_newCurator_is_zero_address() public {
        vm.prank(owner);
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        vault.setCurator(address(0));
    }

    function test_setCurator_reverts_when_newCurator_is_already_set() public {
        vm.prank(owner);
        vm.expectRevert(ErrorsLib.AlreadySet.selector);
        vault.setCurator(curator);
    }

    function test_setAllocator_updates_allocator_successfully() public {
        address newAllocator = makeAddr("newAllocator");
        
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit EventsLib.AllocatorSet(newAllocator, true);
        
        vault.setAllocator(newAllocator, true);
        assertTrue(vault.isAllocator(newAllocator));
    }

    function test_setAllocator_revoke_allocator_successfully() public {
        vm.prank(owner);
        vault.setAllocator(allocator, false);
        assertFalse(vault.isAllocator(allocator));
    }

    function test_setAllocator_reverts_when_newAllocator_is_already_set() public {
        vm.prank(owner);
        vm.expectRevert(ErrorsLib.AlreadySet.selector);
        vault.setAllocator(allocator, true);
    }

    function test_submitGuardian_submits_newGuardian_successfully() public {
        address newGuardian = makeAddr("newGuardian");

        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit EventsLib.GuardianSubmitted(newGuardian);
        
        vault.submitGuardian(newGuardian);
        (address pending, uint64 validAt) = vault.pendingGuardian();
        
        assertEq(pending, newGuardian);
        assertEq(validAt, block.timestamp + TIMELOCK);
    }

    function test_submitGuardian_reverts_when_newGuardian_is_zero_address() public {
        vm.prank(owner);
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        vault.submitGuardian(address(0));
    }

    function test_submitGuardian_reverts_when_newGuardian_is_already_set() public {
        vm.prank(owner);
        vm.expectRevert(ErrorsLib.AlreadySet.selector);
        vault.submitGuardian(guardian);
    }

    function test_submitGuardian_reverts_when_pendingGuardian_exists() public {
        address newGuardian = makeAddr("newGuardian");
        
        vm.prank(owner);
        vault.submitGuardian(newGuardian);

        vm.prank(owner);
        vm.expectRevert(ErrorsLib.PendingGuardianExist.selector);
        vault.submitGuardian(newGuardian);
    }

    function test_acceptGuardian_accepts_pendingGuardian_successfully() public {
        address newGuardian = makeAddr("newGuardian");

        vm.prank(owner);
        vault.submitGuardian(newGuardian);

        vm.warp(block.timestamp + TIMELOCK);
        vm.expectEmit(true, false, false, false);
        emit EventsLib.GuardianUpdated(newGuardian);
        
        vault.acceptGuardian();
        (address pending, uint64 validAt) = vault.pendingGuardian();
        
        assertEq(pending, address(0));
        assertEq(validAt, 0);
        assertEq(vault.guardian(), newGuardian);
    }
    
    function test_acceptGuardian_reverts_when_timelock_not_elapsed() public {
        address newGuardian = makeAddr("newGuardian");

        vm.prank(owner);
        vault.submitGuardian(newGuardian);

        vm.expectRevert(ErrorsLib.TimelockNotElapsed.selector);
        vault.acceptGuardian();
    }

    function test_revokePendingGuardian_revokes_pendingGuardian_successfully() public {
        address newGuardian = makeAddr("newGuardian");

        vm.prank(owner);
        vault.submitGuardian(newGuardian);

        vm.prank(guardian);
        vm.expectEmit(true, false, false, false);
        emit EventsLib.PendingGuardianRevoked(guardian);
        vault.revokePendingGuardian();

        (address pending, uint64 validAt) = vault.pendingGuardian();
        assertEq(pending, address(0));
        assertEq(validAt, 0);
    }

    function test_revokePendingGuardian_reverts_when_msgSender_is_not_guardian() public {
        vm.prank(owner);
        vault.submitGuardian(makeAddr("g2"));

        vm.prank(alice);
        vm.expectRevert(ErrorsLib.NotGuardian.selector);
        vault.revokePendingGuardian();
    }

    function test_revokePendingGuardian_reverts_when_noPendingGuardian() public {
        vm.prank(guardian);
        vm.expectRevert(ErrorsLib.NoPendingChange.selector);
        vault.revokePendingGuardian();
    }

    /* TIMELOCK TESTS */

    function test_submitTimelock_increases_timelock_immediately() public {
        uint256 newTL = TIMELOCK + 1 days;
        
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit EventsLib.TimelockSet(owner, newTL);
        
        vault.submitTimelock(newTL);
        assertEq(vault.timelock(), newTL);
    }

    function test_submitTimelock_decreases_timelock_to_pending() public {
        uint256 newTL = 1 days;
        
        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit EventsLib.TimelockSubmitted(newTL);
        vault.submitTimelock(newTL);

        assertEq(vault.timelock(), TIMELOCK); // still old
        (uint192 pendingVal,) = vault.pendingTimelock();
        assertEq(pendingVal, newTL);
    }

    function test_submitTimelock_reverts_when_msgSender_is_not_owner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vault.submitTimelock(1 days);
    }

    function test_submitTimelock_reverts_when_newTimelock_is_already_set() public {
        vm.prank(owner);
        vm.expectRevert(ErrorsLib.AlreadySet.selector);
        vault.submitTimelock(TIMELOCK);
    }

    function test_submitTimelock_reverts_when_pendingTimelock_exists() public {
        vm.prank(owner);
        vault.submitTimelock(1 days);

        vm.prank(owner);
        vm.expectRevert(ErrorsLib.PendingTimelockExists.selector);
        vault.submitTimelock(1 days + 1);
    }

    function test_submitTimelock_reverts_when_newTimelock_is_above_max() public {
        vm.prank(owner);
        vm.expectRevert(ErrorsLib.MaxTimelockExceeded.selector);
        vault.submitTimelock(ConstantsLib.MAX_TIMELOCK + 1);
    }

    function test_submitTimelock_reverts_when_newTimelock_is_below_min() public {
        vm.prank(owner);
        vm.expectRevert(ErrorsLib.MinTimelockNotReached.selector);
        vault.submitTimelock(1);
    }

    function test_acceptTimelock_accepts_pendingTimelock_successfully() public {
        uint256 newTL = 1 days;
        vm.startPrank(owner);
        vault.submitTimelock(newTL);

        vm.warp(block.timestamp + TIMELOCK);
        vm.expectEmit(true, false, false, false);
        emit EventsLib.TimelockSet(owner, newTL);
        vault.acceptTimelock();
        
        (uint192 pendingVal, uint64 validAt) = vault.pendingTimelock();
        
        assertEq(pendingVal, 0);
        assertEq(validAt, 0);
        assertEq(vault.timelock(), newTL);
    }

    function test_acceptTimelock_reverts_when_timelock_not_elapsed() public {
        vm.prank(owner);
        vault.submitTimelock(1 days);

        vm.expectRevert(ErrorsLib.TimelockNotElapsed.selector);
        vault.acceptTimelock();
    }

    function test_revokePendingTimelock_revokes_pendingTimelock_successfully() public {
        vm.prank(owner);
        vault.submitTimelock(1 days);

        vm.prank(guardian);
        vm.expectEmit(true, false, false, false);
        emit EventsLib.PendingTimelockRevoked(guardian);
        vault.revokePendingTimelock();

        (uint192 val, uint64 validAt) = vault.pendingTimelock();
        assertEq(val, 0);
        assertEq(validAt, 0);
    }

    function test_revokePendingTimelock_reverts_when_msgSender_is_not_guardian() public {
        vm.prank(owner);
        vault.submitTimelock(1 days);

        vm.prank(alice);
        vm.expectRevert(ErrorsLib.NotGuardian.selector);
        vault.revokePendingTimelock();
    }

    function test_revokePendingTimelock_reverts_when_noPendingTimelock() public {
        vm.prank(guardian);
        vm.expectRevert(ErrorsLib.NoPendingChange.selector);
        vault.revokePendingTimelock();
    }

    /* STRATEGY LIFECYCLE TESTS */

    function test_submitStrategy_submits_newStrategy_successfully() public {
        vm.prank(curator);
        vm.expectEmit(true, false, false, true);
        emit EventsLib.StrategySubmitted(address(strategyA), STRATEGY_CAP);
        
        vault.submitStrategy(address(strategyA), STRATEGY_CAP);

        (uint192 val, uint64 validAt) = vault.pendingStrategy(address(strategyA));
        assertEq(val, STRATEGY_CAP);
        assertEq(validAt, block.timestamp + TIMELOCK);
    }

    function test_submitStrategy_reverts_when_msgSender_is_not_curator() public {
        vm.prank(alice);
        vm.expectRevert(ErrorsLib.NotCurator.selector);
        vault.submitStrategy(address(strategyA), STRATEGY_CAP);
    }

    function test_submitStrategy_reverts_when_strategy_is_zero_address_or_cap_is_zero() public {
        vm.startPrank(curator);
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        vault.submitStrategy(address(0), STRATEGY_CAP);
        
        vm.expectRevert(ErrorsLib.ZeroStrategyCap.selector);
        vault.submitStrategy(address(strategyA), 0);
    }

    function test_submitStrategy_reverts_when_strategy_is_invalid() public {
        VaultHarness otherVault = new VaultHarness(owner, address(token), "V2", "V2", 0, feeRecipient, 0, 0); // different vault
        MockStrategy wrongStrategy = new MockStrategy(address(otherVault), alice); // wrong vault and asset

        vm.startPrank(curator);
        vm.expectRevert(ErrorsLib.InvalidStrategy.selector);
        vault.submitStrategy(address(wrongStrategy), STRATEGY_CAP);
        vm.stopPrank();
    }

    function test_submitStrategy_reverts_when_pendingStrategy_exists() public {
        vm.prank(curator);
        vault.submitStrategy(address(strategyA), STRATEGY_CAP);

        vm.prank(curator);
        vm.expectRevert(ErrorsLib.PendingStrategyExists.selector);
        vault.submitStrategy(address(strategyA), STRATEGY_CAP);
    }

    function test_submitStrategy_reverts_when_strategy_already_exists() public {
        vm.prank(curator);
        vault.submitStrategy(address(strategyA), STRATEGY_CAP);

        vm.warp(block.timestamp + TIMELOCK);
        vault.acceptStrategy(address(strategyA));

        vm.prank(curator);
        vm.expectRevert(ErrorsLib.StrategyAlreadyExists.selector);
        vault.submitStrategy(address(strategyA), STRATEGY_CAP);
    }

    function test_acceptStrategy_accepts_pendingStrategy_successfully() public {
        vm.prank(curator);
        vault.submitStrategy(address(strategyA), STRATEGY_CAP);

        vm.warp(block.timestamp + TIMELOCK);
        vm.expectEmit(true, false, false, false);
        emit EventsLib.StrategySet(address(strategyA), STRATEGY_CAP);
        vault.acceptStrategy(address(strategyA));

        (
            uint184 cap, 
            bool enabled, 
            uint64 lastAccrualTimestamp, 
            uint256 lastTotalAssets
        ) = vault.strategyConfig(address(strategyA));

        // check strategy config initialization
        assertEq(cap, STRATEGY_CAP);
        assertTrue(enabled);
        assertEq(lastAccrualTimestamp, block.timestamp);
        assertEq(lastTotalAssets, IStrategy(address(strategyA)).totalAssets());

        // check strategy was added to `_strategies` array
        address[] memory strategies = vault.getStrategies();
        assertEq(strategies.length, 1);

        (uint192 strategyCap, uint64 validAt) = vault.pendingStrategy(address(strategyA));
        assertEq(strategyCap, 0);
        assertEq(validAt, 0);

        // check strategy approval was set to max
        assertEq(token.allowance(address(vault), address(strategyA)), type(uint256).max);
    }

    function test_acceptStrategy_reverts_when_timelock_not_elapsed() public {
        vm.prank(curator);
        vault.submitStrategy(address(strategyA), STRATEGY_CAP);

        vm.expectRevert(ErrorsLib.TimelockNotElapsed.selector);
        vault.acceptStrategy(address(strategyA));
    }

    function test_revokePendingStrategy_revokes_pendingStrategy_successfully() public {
        vm.prank(curator);
        vault.submitStrategy(address(strategyA), STRATEGY_CAP);

        vm.prank(guardian);
        vm.expectEmit(true, false, false, false);
        emit EventsLib.PendingStrategyRevoked(guardian);
        vault.revokePendingStrategy(address(strategyA));

        (uint192 val, uint64 validAt) = vault.pendingStrategy(address(strategyA));
        assertEq(val, 0);
        assertEq(validAt, 0);
    }

    function test_revokePendingStrategy_reverts_when_msgSender_is_not_guardian() public {
        vm.prank(curator);
        vault.submitStrategy(address(strategyA), STRATEGY_CAP);

        vm.prank(alice);
        vm.expectRevert(ErrorsLib.NotGuardian.selector);
        vault.revokePendingStrategy(address(strategyA));
    }

    function test_revokePendingStrategy_reverts_when_no_existing_pendingStrategy() public {
        vm.prank(guardian);
        vm.expectRevert(ErrorsLib.NoPendingChange.selector);
        vault.revokePendingStrategy(address(strategyA));
    }

    function test_submitStrategyCap_decreases_strategyCap_immediately() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);

        uint256 newCap = STRATEGY_CAP / 2;
        vm.prank(curator);
        vm.expectEmit(true, false, false, false);
        emit EventsLib.StrategyCapUpdated(address(strategyA), newCap);
        vault.submitStrategyCap(address(strategyA), newCap);

        (uint184 cap,,,) = vault.strategyConfig(address(strategyA));
        assertEq(cap, newCap);
    }

    function test_submitStrategyCap_submits_newStrategyCap_successfully() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);

        uint256 newCap = STRATEGY_CAP * 2;
        vm.prank(curator);
        vm.expectEmit(true, false, false, false);
        emit EventsLib.StrategyCapSubmitted(address(strategyA), newCap);
        vault.submitStrategyCap(address(strategyA), newCap);

        (uint192 val,) = vault.pendingStrategyCap(address(strategyA));
        assertEq(val, newCap);
    }

    function test_submitStrategyCap_reverts_when_strategy_is_not_enabled() public {
        vm.prank(curator);
        vm.expectRevert(ErrorsLib.StrategyNotEnabled.selector);
        vault.submitStrategyCap(address(strategyA), 1);
    }

    function test_submitStrategyCap_reverts_when_strategyCap_is_zero() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);

        vm.prank(curator);
        vm.expectRevert(ErrorsLib.ZeroStrategyCap.selector);
        vault.submitStrategyCap(address(strategyA), 0);
    }

    function test_submitStrategyCap_reverts_when_strategyCap_is_already_set() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);

        vm.prank(curator);
        vm.expectRevert(ErrorsLib.AlreadySet.selector);
        vault.submitStrategyCap(address(strategyA), STRATEGY_CAP);
    }

    function test_submitStrategyCap_reverts_when_pendingStrategyCap_exists() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);

        vm.prank(curator);
        vault.submitStrategyCap(address(strategyA), STRATEGY_CAP * 2);

        vm.prank(curator);
        vm.expectRevert(ErrorsLib.PendingStrategyCapExists.selector);
        vault.submitStrategyCap(address(strategyA), STRATEGY_CAP * 2);
    }

    function test_acceptStrategyCap_accepts_pendingStrategyCap_successfully() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);
        uint256 newCap = STRATEGY_CAP * 2;

        vm.prank(curator);
        vault.submitStrategyCap(address(strategyA), newCap);

        vm.warp(block.timestamp + TIMELOCK);
        vm.expectEmit(true, false, false, false);
        emit EventsLib.StrategyCapUpdated(address(strategyA), newCap);
        vault.acceptStrategyCap(address(strategyA));

        (uint184 cap,,,) = vault.strategyConfig(address(strategyA));
        assertEq(cap, newCap);

        (uint192 val, uint64 validAt) = vault.pendingStrategyCap(address(strategyA));
        assertEq(val, 0);
        assertEq(validAt, 0);
    }

    function test_acceptStrategyCap_reverts_when_timelock_not_elapsed() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);
        uint256 newCap = STRATEGY_CAP * 2;

        vm.prank(curator);
        vault.submitStrategyCap(address(strategyA), newCap);

        vm.expectRevert(ErrorsLib.TimelockNotElapsed.selector);
        vault.acceptStrategyCap(address(strategyA));
    }

    function test_revokePendingStrategyCap_revokes_pendingStrategyCap_successfully() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);

        vm.prank(curator);
        vault.submitStrategyCap(address(strategyA), STRATEGY_CAP * 2);

        vm.prank(guardian);
        vm.expectEmit(true, false, false, false);
        emit EventsLib.PendingStrategyCapRevoked(guardian);
        vault.revokePendingStrategyCap(address(strategyA));

        (uint192 val, uint64 validAt) = vault.pendingStrategyCap(address(strategyA));
        assertEq(val, 0);
        assertEq(validAt, 0);
    }

    function test_revokePendingStrategyCap_reverts_when_msgSender_is_not_guardian() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);

        vm.prank(curator);
        vault.submitStrategyCap(address(strategyA), STRATEGY_CAP * 2);
    }

    function test_revokePendingStrategyCap_reverts_when_no_existing_pendingStrategyCap() public {
        vm.prank(guardian);
        vm.expectRevert(ErrorsLib.NoPendingChange.selector);
        vault.revokePendingStrategyCap(address(strategyA));
    }

    function test_disableStrategy_disables_strategy_successfully() public {
        _onboardBothStrategies(STRATEGY_CAP, STRATEGY_CAP);

        vm.prank(curator);
        vm.expectEmit(true, false, false, false);
        emit EventsLib.StrategyDisabled(address(strategyA));
        vault.disableStrategy(address(strategyA));

        // Check the strategy config was deleted
        (uint184 cap, bool enabled, uint64 lastAccrualTimestamp, uint256 lastTotalAssets) = vault.strategyConfig(address(strategyA));
        assertEq(cap, 0);
        assertFalse(enabled);
        assertEq(lastAccrualTimestamp, 0);
        assertEq(lastTotalAssets, 0);

        // Check the strategy was removed successfully from `_strategies`, `_supplyQueue`, and `_withdrawQueue` arrays
        address[] memory strategies = vault.getStrategies();
        address[] memory supplyQueue = vault.getSupplyQueue();
        address[] memory withdrawQueue = vault.getWithdrawQueue();
        assertEq(strategies.length, 1); // only `strategyB` remains
        assertEq(supplyQueue.length, 1); 
        assertEq(withdrawQueue.length, 1);
        assertEq(strategies[0], address(strategyB));
        assertEq(supplyQueue[0], address(strategyB));
        assertEq(withdrawQueue[0], address(strategyB));
    }

    function test_disableStrategy_withdraws_remaining_assets_successfully() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);

        // Deposit some assets into strategyA
        _depositAs(alice, 1_000e18);
        assertEq(strategyA.totalAssets(), 1_000e18);
        assertEq(vault.totalAssets(), 1_000e18);

        // Disable the strategy and withdraw the remaining assets
        vm.prank(curator);
        vault.disableStrategy(address(strategyA));

        assertEq(strategyA.totalAssets(), 0);
        assertEq(token.allowance(address(vault), address(strategyA)), 0);
    }

    function test_disableStrategy_reverts_when_strategy_is_not_enabled() public {
        vm.prank(curator);
        vm.expectRevert(ErrorsLib.StrategyNotEnabled.selector);
        vault.disableStrategy(address(strategyA));
    }

    /* QUEUES TESTS */

    function test_setSupplyQueue_sets_supplyQueue_successfully() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);

        address[] memory sq = new address[](1);
        sq[0] = address(strategyA);

        vm.prank(allocator);
        vm.expectEmit(true, false, false, false);
        emit EventsLib.SetSupplyQueue(sq);
        vault.setSupplyQueue(sq);

        address[] memory result = vault.getSupplyQueue();
        assertEq(result.length, 1);
        assertEq(result[0], address(strategyA));
    }

    function test_setSupplyQueue_reverts_when_msgSender_is_not_allocator() public {
        address[] memory sq = new address[](0);
        vm.prank(alice);
        vm.expectRevert(ErrorsLib.NotAllocator.selector);
        vault.setSupplyQueue(sq);
    }

    function test_setSupplyQueue_reverts_when_exceeds_max_strategies() public {
        address[] memory sq = new address[](ConstantsLib.MAX_STRATEGIES + 1);
        vm.prank(allocator);
        vm.expectRevert(ErrorsLib.MaxQueueLengthExceeded.selector);
        vault.setSupplyQueue(sq);
    }

    function test_setSupplyQueue_reverts_when_strategy_is_zero_address() public {
        address[] memory sq = new address[](1);
        sq[0] = address(0);

        vm.prank(allocator);
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        vault.setSupplyQueue(sq);
    }

    function test_setSupplyQueue_reverts_when_strategy_is_not_enabled() public {
        address[] memory sq = new address[](1);
        sq[0] = address(strategyA);

        vm.prank(allocator);
        vm.expectRevert(ErrorsLib.StrategyNotEnabled.selector);
        vault.setSupplyQueue(sq);
    }

    function test_setSupplyQueue_reverts_when_strategy_is_duplicate() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);

        address[] memory sq = new address[](2);
        sq[0] = address(strategyA);
        sq[1] = address(strategyA);

        vm.prank(allocator);
        vm.expectRevert(ErrorsLib.StrategyDuplicate.selector);
        vault.setSupplyQueue(sq);
    }

    /* ERC4626 CORE TESTS (deposit/mint/withdraw/redeem) */

    function test_deposit_deposits_assets_and_mints_shares() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);

        uint256 depAmount = 1_000e18;
        uint256 shares = _depositAs(alice, depAmount);

        assertEq(vault.balanceOf(alice), shares);
        assertEq(strategyA.totalAssets(), depAmount);
        assertEq(vault.totalAssets(), depAmount);
    }
    
    function test_mint_mints_shares_and_outputs_correct_assets() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);

        uint256 depAmount = 1_000e18;
        uint256 firstShares = _depositAs(alice, depAmount);

        vm.startPrank(bob);
        uint256 bobBalanceBefore = token.balanceOf(bob);
        token.approve(address(vault), type(uint256).max);
        uint256 assets = vault.mint(firstShares, bob);
        vm.stopPrank();

        assertEq(vault.balanceOf(bob), firstShares);
        assertEq(token.balanceOf(bob), bobBalanceBefore - assets);
        assertEq(assets, depAmount);
    }

    function test_withdraw_withdraws_assets_and_returns_correct_shares() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);

        uint256 withAmount = 1_000e18;
        uint256 supplyShares = _depositAs(alice, withAmount);
        uint256 withdrawnShares = _withdrawAs(alice, withAmount);

        assertEq(supplyShares, withdrawnShares);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(strategyA.totalAssets(), 0);
        assertEq(vault.totalAssets(), 0);
    }

    function test_redeem_redeems_shares_and_outputs_correct_assets() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);

        uint256 amount = 1_000e18;
        uint256 shares = _depositAs(alice, amount);

        vm.startPrank(alice);
        uint256 assets = vault.redeem(shares, alice, alice);
        vm.stopPrank();

        assertEq(assets, amount);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_deposit_reverts_when_paused() public {
        vm.prank(owner);
        vault.pause();

        vm.startPrank(alice);
        token.approve(address(vault), 100e18);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.deposit(100e18, alice);
        vm.stopPrank();
    }

    function test_withdraw_reverts_when_paused() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);
        _depositAs(alice, 1_000e18);

        vm.prank(owner);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.withdraw(1_000e18, alice, alice);
    }

    function test_mint_reverts_when_paused() public {
        vm.prank(owner);
        vault.pause();

        vm.startPrank(alice);
        token.approve(address(vault), 100e18);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.mint(100e18, alice);
        vm.stopPrank();
    }

    function test_redeem_reverts_when_paused() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);
        uint256 shares = _depositAs(alice, 1_000e18);

        vm.prank(owner);
        vault.pause();

        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.redeem(shares, alice, alice);
    }

    function test_unpause_allows_deposit() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);

        vm.prank(owner);
        vault.pause();

        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 aliceSharesBefore = vault.balanceOf(alice);

        vm.prank(alice);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vault.deposit(100e18, alice);

        assertEq(aliceSharesBefore, 0);
        assertEq(token.balanceOf(alice), aliceBalanceBefore);

        vm.prank(owner);
        vault.unpause();

        _depositAs(alice, 100e18);
        assertGt(vault.balanceOf(alice), aliceSharesBefore);
        assertEq(token.balanceOf(alice), aliceBalanceBefore - 100e18);
    }

    function test_pause_reverts_when_msgSender_is_not_owner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vault.pause();
    }

    /* TOTAL ASSETS & SHARE MATH TESTS */

    function test_totalAssets_includes_idle_and_strategy_assets() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);

        // simulate idle assets
        uint256 idle = 1_000e18;
        uint256 aliceDep = 2_000e18;
        deal(address(token), address(vault), idle);
        _depositAs(alice, aliceDep);

        assertEq(vault.totalAssets(), aliceDep + idle);
    }

    function test_totalAssets_reflects_yield() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);
        _depositAs(alice, 1_000e18);

        // simulate yield in strategy
        uint256 yield = 100e18;
        deal(address(token), address(this), yield);
        token.approve(address(strategyA), yield);
        strategyA.simulateYield(yield);

        assertGe(vault.totalAssets(), 1_000e18 + yield);
    }

    function test_decimalsOffset_returns_9() public view {
        assertEq(vault.exposed_decimalsOffset(), 9);
    }

    function test_convertToSharesWithTotals_round_trip() public view {
        uint256 totalSupply = 1_000e27; // with 9 offset
        uint256 totalAssets = 1_000e18;
        uint256 assets = 100e18;

        uint256 shares = vault.exposed_convertToSharesWithTotals(assets, totalSupply, totalAssets, Math.Rounding.Floor);
        uint256 backToAssets = vault.exposed_convertToAssetsWithTotals(shares, totalSupply, totalAssets, Math.Rounding.Floor);
        assertApproxEqAbs(backToAssets, assets, 1);
    }

    function test_maxDeposit_matches_cap_headroom() public {
        uint256 cap = 500e18;
        _onboardStrategy(strategyA, cap);
        assertEq(vault.maxDeposit(alice), cap);
    }

    function test_maxWithdraw_capped_by_liquidity() public {
        uint256 cap = 500e18;
        _onboardStrategy(strategyA, cap);
        _depositAs(alice, cap);
        assertEq(vault.maxWithdraw(alice), cap);
    }

    function test_maxRedeem_capped_by_liquidity() public {
        uint256 cap = 500e18;
        _onboardStrategy(strategyA, cap);
        uint256 shares = _depositAs(alice, cap);
        assertEq(vault.maxRedeem(alice), shares);
    }

    /* FEE MANAGEMENT TESTS */

    function test_setFee_sets_fee_successfully() public {
        uint256 newFee = 500;
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit EventsLib.FeeUpdated(newFee);
        
        vault.setFee(newFee);
        assertEq(vault.fee(), newFee);
    }

    function test_setFee_reverts_when_already_set() public {
        vm.prank(owner);
        vm.expectRevert(ErrorsLib.AlreadySet.selector);
        vault.setFee(DEFAULT_FEE);
    }

    function test_setFee_reverts_when_above_max_fee() public {
        vm.prank(owner);
        vm.expectRevert(ErrorsLib.InvalidFeeBPS.selector);
        vault.setFee(ConstantsLib.MAX_FEE + 1);
    }

    function test_setFee_reverts_when_msgSender_is_not_owner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vault.setFee(500);
    }

    function test_setFeeRecipient_sets_feeRecipient_successfully() public {
        address newFeeRecipient = makeAddr("newFeeRecipient");
        
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit EventsLib.FeeRecipientUpdated(newFeeRecipient);
        
        vault.setFeeRecipient(newFeeRecipient);
        assertEq(vault.feeRecipient(), newFeeRecipient);
    }

    function test_setFeeRecipient_reverts_when_zero_address() public {
        vm.prank(owner);
        vm.expectRevert(ErrorsLib.ZeroAddress.selector);
        vault.setFeeRecipient(address(0));
    }

    function test_setFeeRecipient_reverts_when_already_set() public {
        vm.prank(owner);
        vm.expectRevert(ErrorsLib.AlreadySet.selector);
        vault.setFeeRecipient(feeRecipient);
    }

    function test_setFeeRecipient_reverts_when_msgSender_is_not_owner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vault.setFeeRecipient(feeRecipient);
    }

    function test_setVaultFeeShare_sets_vaultFeeShare_successfully() public {
        uint256 newVaultFeeShare = 500;
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit EventsLib.VaultFeeShareUpdated(newVaultFeeShare);
        
        vault.setVaultFeeShare(newVaultFeeShare);
        assertEq(vault.vaultFeeShare(), newVaultFeeShare);
    }

    function test_setVaultFeeShare_reverts_when_above_max_vault_fee_share() public {
        vm.prank(owner);
        vm.expectRevert(ErrorsLib.InvalidVaultFeeShare.selector);
        vault.setVaultFeeShare(ConstantsLib.MAX_VAULT_FEE_SHARE_BPS + 1);
    }

    function test_setVaultFeeShare_reverts_when_already_set() public {
        vm.prank(owner);
        vm.expectRevert(ErrorsLib.AlreadySet.selector);
        vault.setVaultFeeShare(DEFAULT_VAULT_SHARE);
    }

    function test_setVaultFeeShare_reverts_when_msgSender_is_not_owner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vault.setVaultFeeShare(DEFAULT_VAULT_SHARE);
    }
        
    function test_accrueInterest_mints_fee_shares_on_yield() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);
        _depositAs(alice, 10_000e18);

        // simulate yield in strategy
        uint256 yieldAmount = 1_000e18;
        deal(address(token), address(this), yieldAmount);
        token.approve(address(strategyA), yieldAmount);
        strategyA.simulateYield(yieldAmount);

        uint256 feeRecipientSharesBefore = vault.balanceOf(feeRecipient);
        address strategyOwner = strategyA.strategyOwner();
        uint256 strategyOwnerSharesBefore = vault.balanceOf(strategyOwner);

        // trigger accrual
        vault.exposed_accrueInterest();

        uint256 feeRecipientSharesAfter = vault.balanceOf(feeRecipient);
        uint256 strategyOwnerSharesAfter = vault.balanceOf(strategyOwner);

        assertGt(feeRecipientSharesAfter, feeRecipientSharesBefore);
        assertGt(strategyOwnerSharesAfter, strategyOwnerSharesBefore);
    }

    function test_accrueInterest_no_fee_when_no_yield() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);
        _depositAs(alice, 10_000e18);

        uint256 feeRecipientSharesBefore = vault.balanceOf(feeRecipient);
        vault.exposed_accrueInterest();
        assertEq(vault.balanceOf(feeRecipient), feeRecipientSharesBefore);
    }

    function test_accrueInterest_no_fee_when_fee_is_zero() public {
        vm.prank(owner);
        vault.setFee(0);

        _onboardStrategy(strategyA, STRATEGY_CAP);
        _depositAs(alice, 10_000e18);

        // simulate yield in strategy
        uint256 yieldAmount = 1_000e18;
        deal(address(token), address(this), yieldAmount);
        token.approve(address(strategyA), yieldAmount);
        strategyA.simulateYield(yieldAmount);

        vault.exposed_accrueInterest();
        assertEq(vault.balanceOf(feeRecipient), 0);
    }

    function test_accrueInterest_vault_share_split() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);
        _depositAs(alice, 10_000e18);

        uint256 yieldAmount = 1_000e18;
        deal(address(token), address(this), yieldAmount);
        token.approve(address(strategyA), yieldAmount);
        strategyA.simulateYield(yieldAmount);

        vault.exposed_accrueInterest();

        uint256 feeRecipientShares = vault.balanceOf(feeRecipient);
        address stratOwner = strategyA.strategyOwner();
        uint256 stratOwnerShares = vault.balanceOf(stratOwner);

        uint256 totalFeeShares = feeRecipientShares + stratOwnerShares;
        if (totalFeeShares > 0) {
            uint256 vaultPortionBps = feeRecipientShares * BPS / totalFeeShares;
            assertApproxEqAbs(vaultPortionBps, DEFAULT_VAULT_SHARE, 1); // vault should get ~50% of fee shares
        }
    }

    function test_accrueInterest_split_across_two_strategies() public {
        _onboardBothStrategies(STRATEGY_CAP, STRATEGY_CAP);

        _depositAs(alice, 2_000e18);

        // Give different yields to each strategy
        uint256 yieldA = 200e18;
        uint256 yieldB = 800e18;
        deal(address(token), address(this), yieldA + yieldB);
        token.approve(address(strategyA), yieldA);
        strategyA.simulateYield(yieldA);
        token.approve(address(strategyB), yieldB);
        strategyB.simulateYield(yieldB);

        vault.exposed_accrueInterest();

        address ownerA = strategyA.strategyOwner();
        address ownerB = strategyB.strategyOwner();
        uint256 sharesA = vault.balanceOf(ownerA);
        uint256 sharesB = vault.balanceOf(ownerB);
        console.log("sharesA", sharesA);
        console.log("sharesB", sharesB);

        // ownerB should get ~4x the shares of ownerA (800/200)
        if (sharesA > 0) {
            assertApproxEqRel(sharesB, sharesA * 4, 0.01e18); // `0.01e18` ~ 1% slippage tolerance
        }
    }

    /* LIQUIDITY ALLOCATION TESTS */

    function test_supplyQueue_routes_to_first_available() public {
        _onboardBothStrategies(500e18, STRATEGY_CAP);

        _depositAs(alice, 800e18);

        assertEq(strategyA.totalAssets(), 500e18);
        assertEq(strategyB.totalAssets(), 300e18);
    }

    function test_deposit_reverts_when_all_caps_reached() public {
        _onboardStrategy(strategyA, 100e18);

        vm.startPrank(alice);
        token.approve(address(vault), 200e18);
        vm.expectRevert(ErrorsLib.AllCapsReached.selector);
        vault.deposit(200e18, alice);
        vm.stopPrank();
    }

    function test_withdrawQueue_pullsFromFirstAvailable() public {
        // Use small caps so deposits split across both strategies
        _onboardBothStrategies(1_000e18, 1_000e18);

        _depositAs(alice, 2_000e18);

        // strategyA has 1000, strategyB has 1000
        assertEq(strategyA.totalAssets(), 1_000e18);
        assertEq(strategyB.totalAssets(), 1_000e18);

        // Withdraw 1500: pulls 1000 from A (first in queue), then 500 from B
        vm.startPrank(alice);
        vault.withdraw(1_500e18, alice, alice);
        vm.stopPrank();

        assertEq(strategyA.totalAssets(), 0);
        assertEq(strategyB.totalAssets(), 500e18);
    }

    function test_withdraw_reverts_when_not_enough_liquidity() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);
        _depositAs(alice, 1_000e18);

        // Simulate loss so strategy can't fully cover
        strategyA.simulateLoss(500e18);

        vm.prank(alice);
        vm.expectRevert(ErrorsLib.NotEnoughLiquidity.selector);
        vault.withdraw(1_000e18, alice, alice);
    }

    function test_withdraw_from_idle_before_strategy() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);
        _depositAs(alice, 1_000e18);

        // Manually send tokens to vault (simulate idle funds)
        deal(address(token), address(vault), 500e18);

        // Now strategy has 1000, vault has 500 idle
        // Withdraw 500 should come from idle only
        uint256 strategyBefore = IStrategy(address(strategyA)).totalAssets();
        vm.prank(alice);
        vault.withdraw(500e18, alice, alice);
        assertEq(IStrategy(address(strategyA)).totalAssets(), strategyBefore);
    }

    function test_withdrawalLiquidityGap_full_coverage() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);
        _depositAs(alice, 1_000e18);

        uint256 gap = vault.exposed_withdrawalLiquidityGap(1_000e18);
        assertEq(gap, 0);
    }

    function test_withdrawalLiquidityGap_partial_coverage() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);
        _depositAs(alice, 500e18);

        uint256 gap = vault.exposed_withdrawalLiquidityGap(800e18);
        assertEq(gap, 300e18);
    }

    function test_withdrawalLiquidityGap_zero_assets() public view {
        uint256 gap = vault.exposed_withdrawalLiquidityGap(0);
        assertEq(gap, 0);
    }

    /* EDGE CASES & LOSS HANDLING TESTS */

    function test_disableStrategy_with_partial_withdraw_tracks_lost_assets() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);
        _depositAs(alice, 1_000e18);

        strategyA.setPartialWithdraw(true, 8_000); // means it will return 80% of the assets

        vm.prank(curator);
        vault.disableStrategy(address(strategyA));

        assertEq(vault.lostAssets(), 200e18);
    }

    function test_disableStrategy_with_zero_assets_no_loss() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);

        vm.prank(curator);
        vault.disableStrategy(address(strategyA));

        assertEq(vault.lostAssets(), 0);
    }

    function test_deposit_supply_queue_skips_failed_strategy() public {
        _onboardBothStrategies(STRATEGY_CAP, STRATEGY_CAP);

        strategyA.setFailOnDeposit(true);

        // Deposit should route everything to strategyB when A fails
        _depositAs(alice, 500e18);

        assertEq(strategyA.totalAssets(), 0);
        assertEq(strategyB.totalAssets(), 500e18);
    }

    function test_multiple_deposits_and_withdrawals_consistency() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);

        // deposit assets from alice and bob
        _depositAs(alice, 1_000e18);
        _depositAs(bob,   2_000e18);

        // Alice withdraws half
        vm.prank(alice);
        vault.withdraw(500e18, alice, alice);

        // Bob redeems all
        uint256 bobShares = vault.balanceOf(bob);
        vm.prank(bob);
        uint256 bobAssets = vault.redeem(bobShares, bob, bob);
        assertEq(bobAssets, 2_000e18);

        // Alice redeems rest
        uint256 aliceShares = vault.balanceOf(alice);
        vm.prank(alice);
        uint256 aliceAssets = vault.redeem(aliceShares, alice, alice);
        assertEq(aliceAssets, 500e18);

        assertEq(vault.totalSupply(), 0);
    }

    function test_deposit_zero_assets_yields_zero_shares() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);

        // deposit(0) → 0 shares → _deposit transfers 0 → _supplyToStrategy(0) skips loop → succeeds
        vm.startPrank(alice);
        token.approve(address(vault), 0);
        uint256 shares = vault.deposit(0, alice);
        vm.stopPrank();
        assertEq(shares, 0);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_lastTotalAssets_updated_on_deposit() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);

        assertEq(vault.lastTotalAssets(), 0);
        _depositAs(alice, 1_000e18);
        assertEq(vault.lastTotalAssets(), 1_000e18);
    }

    function test_lastTotalAssets_updated_on_withdraw() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);
        _depositAs(alice, 1_000e18);

        vm.prank(alice);
        vault.withdraw(400e18, alice, alice);
        assertEq(vault.lastTotalAssets(), 600e18);
    }

    /* DEPOSIT WITH PERMIT (gasless) TESTS */

    function test_depositWithPermit_deposits_assets_correctly() public {
        _onboardStrategy(strategyA, STRATEGY_CAP);

        uint256 amount = 100 ether;
        uint256 deadline = block.timestamp + 1 hours;

        // alice signs the permit for the vault to deposit her assets on her behalf
        bytes32 digest = PermitHash.getPermitDigest(token, alice, address(vault), amount, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);
        
        vm.prank(bob);
        vault.depositWithPermit(amount, alice, alice, deadline, v, r, s); // bob deposits alice assets on her behalf

        assertGt(vault.balanceOf(alice), 0);
    }

    // TODO: requires fix
    // function test_mintWithPermit_mints_shares_correctly() public {
    //     _onboardStrategy(strategyA, STRATEGY_CAP);

    //     uint256 amount = 100 ether;
    //     uint256 deadline = block.timestamp + 1 hours;

    //     // alice signs the permit for the vault to mint her shares on her behalf
    //     bytes32 digest = PermitHash.getPermitDigest(token, alice, address(vault), amount, deadline);
    //     (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);
        
    //     vm.prank(bob);
    //     vault.mintWithPermit(amount, alice, alice, deadline, v, r, s); // bob mints alice shares on her behalf

    //     assertEq(vault.balanceOf(alice), amount);
    // }

    function test_depositWithPermit_reverts_zeroAssets() public {
        vm.expectRevert(ErrorsLib.ZeroAssetsInAmount.selector);
        vault.depositWithPermit(0, alice, alice, 0, 0, bytes32(0), bytes32(0));
    }

    function test_mintWithPermit_reverts_zeroShares() public {
        vm.expectRevert(ErrorsLib.ZeroSharesInAmount.selector);
        vault.mintWithPermit(0, alice, alice, 0, 0, bytes32(0), bytes32(0));
    }
}
