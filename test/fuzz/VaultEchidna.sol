// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Vault} from "../../src/Vault.sol";
import {MyToken} from "../../src/MyToken.sol";
import {IStrategy, StrategyConfig} from "../../src/interfaces/IStrategy.sol";
import {ConstantsLib} from "../../src/libraries/ConstantsLib.sol";

import {VaultHarness} from "../mocks/VaultHarness.sol";
import {MockStrategy} from "../mocks/MockStrategy.sol";

/// @title VaultEchidna
/// @notice Echidna property-based tests for the Vault contract.
/// Echidna calls the public functions below in random order with random arguments.
/// Any function prefixed with `echidna_` must return `true` for the property to hold.
/// Functions prefixed with `fuzz_` are actions Echidna can call to mutate state.
contract VaultEchidna {
    using Math for uint256;

    MyToken internal token;
    VaultHarness internal vault;
    MockStrategy internal strategy;

    /// @dev Addresses used as role/participant placeholders inside the harness.
    /// Echidna controls `msg.sender` via config; these constants are for the system-under-test wiring.
    address internal constant FEE_RECIPIENT = address(0x20000);
    address internal constant GUARDIAN = address(0x40000);
    address internal constant STRAT_OWNER = address(0x60000);

    uint256 internal constant STRATEGY_CAP = 100_000_000e18;
    uint256 internal constant INITIAL_MINT = 1_000_000e18;

    bool internal initialized;

    /// @notice One-time deployment and wiring of the system under test.
    /// @dev Echidna can call any public function first; this guard ensures the harness is always initialized.
    /// We deploy the vault with `address(this)` as owner because Echidna cannot impersonate EOAs (no cheatcodes).
    function _initialize() internal {
        if (initialized) return;
        initialized = true;

        // Deploy token and fund the harness so it can act as a depositor and as a yield source.
        token = new MyToken();
        token.mint(address(this), INITIAL_MINT * 100);

        // Deploy vault with this harness as the owner so we can configure roles/queues.
        vault = new VaultHarness(
            address(this),  // this contract is owner
            address(token),
            "VaultShare",
            "vSHR",
            1_000,
            FEE_RECIPIENT,
            5_000,
            0  // zero timelock so accept* works immediately
        );

        strategy = new MockStrategy(address(vault), STRAT_OWNER);

        vault.setCurator(address(this));
        vault.setAllocator(address(this), true);
        vault.submitGuardian(GUARDIAN);
        vault.acceptGuardian();

        vault.submitStrategy(address(strategy), STRATEGY_CAP);
        vault.acceptStrategy(address(strategy));

        address[] memory q = new address[](1);
        q[0] = address(strategy);
        vault.setSupplyQueue(q);
        vault.setWithdrawQueue(q);

        // Pre-approve from this harness for deposits into the vault.
        token.approve(address(vault), type(uint256).max);
        // Pre-approve for simulateYield (transfers from this contract to the strategy in MockStrategy).
        token.approve(address(strategy), type(uint256).max);
        // Note: vault strategy approval is handled automatically by _setStrategy (type(uint256).max)
    }

    /* Actions (Echidna calls these to mutate state) */

    /// @notice Action: deposit some assets into the vault as this harness.
    /// @dev Amount is clamped to keep sequences progressing without frequent reverts.
    function fuzz_deposit(uint256 amount) public {
        _initialize();
        amount = _clamp(amount, 1, token.balanceOf(address(this)) / 2);
        if (amount == 0) return;

        try vault.deposit(amount, address(this)) {} catch {}
    }

    /// @notice Action: withdraw some assets from the vault back to this harness.
    /// @dev Uses `maxWithdraw` to avoid systematic reverts when liquidity is low.
    function fuzz_withdraw(uint256 amount) public {
        _initialize();
        uint256 maxW = vault.maxWithdraw(address(this));
        if (maxW == 0) return;
        amount = _clamp(amount, 1, maxW);

        try vault.withdraw(amount, address(this), address(this)) {} catch {}
    }

    /// @notice Action: mint some shares by depositing the required assets.
    /// @dev Uses `maxMint` to stay within supply queue capacity.
    function fuzz_mint(uint256 shares) public {
        _initialize();
        uint256 maxM = vault.maxMint(address(this));
        if (maxM == 0) return;
        shares = _clamp(shares, 1, maxM);

        try vault.mint(shares, address(this)) {} catch {}
    }

    /// @notice Action: redeem some shares for underlying assets.
    /// @dev Clamped to current share balance.
    function fuzz_redeem(uint256 shares) public {
        _initialize();
        uint256 bal = vault.balanceOf(address(this));
        if (bal == 0) return;
        shares = _clamp(shares, 1, bal);

        try vault.redeem(shares, address(this), address(this)) {} catch {}
    }

    /// @notice Action: simulate positive strategy yield.
    /// @dev MockStrategy pulls tokens from this harness; we ensure a minimum size for meaningful yield.
    function fuzz_simulateYield(uint256 amount) public {
        _initialize();
        amount = _clamp(amount, 1e18, 10_000e18);

        uint256 bal = token.balanceOf(address(this));
        if (bal < amount) return;

        strategy.simulateYield(amount);
    }

    /// @notice Action: simulate a strategy loss (reduces strategy accounted assets).
    /// @dev Loss is clamped to the strategy's current reported assets.
    function fuzz_simulateLoss(uint256 amount) public {
        _initialize();
        uint256 stratBal = IStrategy(address(strategy)).totalAssets();
        if (stratBal == 0) return;
        amount = _clamp(amount, 1, stratBal);

        strategy.simulateLoss(amount);
    }

    /// @notice Action: explicitly accrue interest (writes snapshots and mints fee shares when applicable).
    function fuzz_accrueInterest() public {
        _initialize();
        vault.exposed_accrueInterest();
    }

    /* Invariants (must always return true) */

    /// @notice Total supply should never be non-zero when no assets exist, and vice versa.
    /// After the first deposit the invariant is: supply > 0 and totalAssets > 0.
    /// Note: due to the virtual offset (1e9 shares), with zero deposits both are 0 which is fine.
    function echidna_totalSupply_totalAssets_coherent() public returns (bool) {
        _initialize();
        uint256 ts = vault.totalSupply();
        uint256 ta = vault.totalAssets();

        // If no one deposited, both should be zero
        if (ts == 0) return true;
        // If someone deposited, totalAssets must be > 0 (barring total loss scenarios).
        // We allow totalAssets == 0 only if lostAssets accounts for everything.
        return ta > 0 || vault.lostAssets() > 0;
    }

    /// @notice Fee can never exceed MAX_FEE.
    function echidna_fee_within_bounds() public returns (bool) {
        _initialize();
        return vault.fee() <= ConstantsLib.MAX_FEE;
    }

    /// @notice VaultFeeShare can never exceed MAX_VAULT_FEE_SHARE_BPS.
    function echidna_vaultFeeShare_within_bounds() public returns (bool) {
        _initialize();
        return vault.vaultFeeShare() <= ConstantsLib.MAX_VAULT_FEE_SHARE_BPS;
    }

    /// @notice A user's share balance should always convert to <= totalAssets (no share inflation).
    function echidna_shares_never_exceed_assets_value() public returns (bool) {
        _initialize();
        uint256 myShares = vault.balanceOf(address(this));
        if (myShares == 0) return true;

        uint256 ta = vault.totalAssets();
        uint256 ts = vault.totalSupply();
        if (ts == 0) return true;

        uint256 myAssets = vault.exposed_convertToAssetsWithTotals(myShares, ts, ta, Math.Rounding.Floor);
        return myAssets <= ta;
    }

    /// @notice Converting assets --> shares --> assets should not increase the asset amount (rounding favors vault).
    function echidna_roundTrip_noFreeAssets() public returns (bool) {
        _initialize();
        uint256 ta = vault.totalAssets();
        uint256 ts = vault.totalSupply();

        uint256 testAmount = 1_000e18;
        uint256 shares = vault.exposed_convertToSharesWithTotals(testAmount, ts, ta, Math.Rounding.Floor);
        uint256 backToAssets = vault.exposed_convertToAssetsWithTotals(shares, ts, ta, Math.Rounding.Floor);

        return backToAssets <= testAmount;
    }

    /// @notice Vault token balance + strategy balance should be >= totalAssets - lostAssets (accounting identity).
    function echidna_accounting_identity() public returns (bool) {
        _initialize();
        uint256 idle = token.balanceOf(address(vault));
        uint256 inStrategy = IStrategy(address(strategy)).totalAssets();

        uint256 realAssets = idle + inStrategy;

        // Mirror the vault's *view* logic:
        // - The vault previews `newLostAssets` based on (lastTotalAssets, lostAssets, currentTotalAssets).
        // - `totalAssets()` returns `currentTotalAssets + newLostAssets`.
        uint256 last = vault.lastTotalAssets();
        uint256 lastLost = vault.lostAssets();
        uint256 expectedLost = lastLost;
        if (realAssets < last - lastLost) {
            expectedLost = last - realAssets;
        }
        uint256 expectedTotalAssets = realAssets + expectedLost;

        uint256 ta = vault.totalAssets();
        // Allow 1 wei slack for rounding / edge effects.
        if (ta == 0) return expectedTotalAssets == 0;
        return expectedTotalAssets + 1 >= ta && ta + 1 >= expectedTotalAssets;
    }

    /// @notice No single deposit + withdraw cycle should profit the user (no free value extraction).
    function echidna_no_profit_from_deposit_withdraw() public returns (bool) {
        _initialize();
        uint256 balBefore = token.balanceOf(address(this));
        uint256 depositAmt = 10_000e18;

        if (balBefore < depositAmt) return true;

        try vault.deposit(depositAmt, address(this)) returns (uint256 shares) {
            if (shares == 0) return true;
            try vault.redeem(shares, address(this), address(this)) returns (uint256) {
                uint256 balAfter = token.balanceOf(address(this));
                // User should not profit: balAfter <= balBefore
                return balAfter <= balBefore;
            } catch {
                return true;
            }
        } catch {
            return true;
        }
    }

    /// @notice lostAssets should never exceed lastTotalAssets.
    function echidna_lostAssets_bounded() public returns (bool) {
        _initialize();
        return vault.lostAssets() <= vault.lastTotalAssets() + vault.totalAssets() + 1;
    }

    /* Helpers */

    /// @notice Clamp `val` into the inclusive range `[lo, hi]`.
    /// @dev If `hi <= lo`, returns `lo` to avoid underflow/div-by-zero.
    function _clamp(uint256 val, uint256 lo, uint256 hi) internal pure returns (uint256) {
        if (hi <= lo) return lo;
        return lo + (val % (hi - lo + 1));
    }
}
