# Strategy Vault

An ERC-4626 yield vault with a **permissionless strategy marketplace**, timelocks for critical actions, role-based access control, gasless deposits via ERC-2612 permit, and a performance fee model that splits yield between the vault protocol and strategy creators.

> **IMPORTANT**: 
> - This project is a prototype for demonstration and learning purposes. It has not been audited and is not production-ready.
> - The project is still in the development phase, so the architecture, approaches and code will change over the time.

## Overview

The vault accepts a single underlying asset (e.g. USDC) and allocates it across multiple yield-generating strategies. Anyone can build and propose a strategy; only the curator can approve it (subject to a timelock). Depositors receive ERC-4626 shares representing their proportional claim on the vault's total assets (idle + deployed across strategies).

### Key Features

- **Permissionless strategy marketplace** -- anyone can deploy a strategy contract and propose it to the vault. Strategies can range from simple (supply to Aave) to advanced (leverage loops). Strategy creators earn a share of the yield their strategy generates.
- **Morpho-style timelocks** -- critical changes (adding strategies, increasing caps, changing guardian, decreasing timelock) go through a submit/wait/accept flow. Users can exit during the timelock window if they disagree with a pending change.
- **Role-based access control** -- three roles (owner, curator, guardian) with separated privileges for protocol governance, risk management, and safety.
- **Gasless deposits** -- deposit and mint via ERC-2612 permit signatures, enabling relayer-submitted transactions.
- **Performance fee with strategist split** -- fees are taken only on positive yield (no deposit/withdraw fees). The fee is split between the vault protocol (`feeRecipient`) and strategy creators proportional to each strategy's yield contribution, which means the more strategy generate yield the bigger shares proporting the strategy owner will receive.

## Architecture
![Architecture](./img/Strategy_Vault_Architecture.jpg)

Each vault holds **one underlying asset**. Strategies implement the `IStrategy` interface and inherit from `BaseStrategy`, which enforces vault-only access on deposit/withdraw. The vault tracks each strategy's configuration (cap, enabled status, yield snapshot) and aggregates their balances in `totalAssets()`.

## Roles

| Role | Responsibilities |
|------|-----------------|
| **Owner** | Protocol-level settings: set curator, submit guardian (timelocked), submit timelock (timelocked), set performance fee, set fee recipient, set vault fee share. Uses `Ownable2Step` for safe transfers. |
| **Curator** | Risk management: approve proposed strategies (timelocked), set strategy caps, manage withdraw queue, reallocate funds between strategies, emergency withdraw. |
| **Guardian** | Safety backstop: revoke any pending timelocked change. Changing the guardian is itself timelocked. |

## Timelocks

Modeled after MetaMorpho's `PendingLib` pattern. A global `timelock` duration applies to sensitive actions.

**Three-step flow:**
1. `submit*()` -- owner or curator proposes a change, starts the timelock.
2. Wait -- the timelock duration passes. Guardian can `revoke*()` to cancel.
3. `accept*()` -- anyone can finalize the change after the timelock expires.

**Asymmetric rules:** changes that reduce risk (decrease caps, remove strategies, increase timelock) take effect instantly. Changes that increase risk (add strategies, increase caps, decrease timelock) require waiting through the timelock.

## Strategy Marketplace

1. A strategy owner deploys a contract extending `BaseStrategy` with `strategyOwner()` returning their address.
2. The strategy is proposed to the vault via `proposeStrategy()`.
3. The curator reviews the strategy off-chain, then calls `submitStrategy()` to begin timelocked approval.
4. After the timelock, `acceptStrategy()` activates the strategy.
5. The curator allocates funds to the strategy via `reallocate()`.
6. The strategy generates yield. On fee accrual, the performance fee is split: `vaultFeeShare` goes to `feeRecipient`, the rest is distributed to strategy creators proportional to each strategy's yield.

## Fees
- No deposit or withdrawal fees.
- Performance fee (`fee` in BPS, max 20% at the moment) is taken on positive yield only.
- `_accrueInterest()` runs on every deposit/withdraw/mint/redeem to keep share price accurate.
- Fee is minted as new shares (not transferred as assets).
- The fee is split: `vaultFeeShare` (max 70%) goes to `feeRecipient`, the remainder is distributed among strategy creators proportional to their strategy's yield contribution.

## Contracts

| Contract | Description |
|----------|-------------|
| `Vault.sol` | Core ERC-4626 vault with strategy management, timelocks, roles, fee accrual, and gasless deposits. |
| `VaultFactory.sol` | Factory for deploying and indexing vault instances. |
| `BaseStrategy.sol` | Abstract base for all strategies. Enforces vault-only access via template method pattern. |
| `IStrategy.sol` | Strategy interface + `StrategyConfig` struct. |
| `IVault.sol` | Vault interface. |
| `IVaultFactory.sol` | Factory interface. |
| `PendingLib.sol` | Timelock primitives (`PendingUint192`, `PendingAddress`) with `update()` helpers. |
| `ConstantsLib.sol` | Protocol constants (max fee, timelock bounds, BPS denominator). |
| `ErrorsLib.sol` | Custom errors for all project contracts. |
| `EventsLib.sol` | Events for all project contracts. |
| `MyToken.sol` | ERC-20 test token with ERC-2612 permit support. |

## Building and Testing

This project uses [Foundry](https://book.getfoundry.sh/).

```bash
# Install dependencies
forge install

# Build
forge build

# Run tests
forge test

# Run tests with verbosity
forge test -vvv
```

## Tech Stack

- **Solidity** 0.8.30
- **Foundry**
- **OpenZeppelin Contracts**