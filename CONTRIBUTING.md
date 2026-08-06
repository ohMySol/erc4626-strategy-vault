# Contributing to Strategy Vault

Thank you for your interest in contributing to the ERC-4626 Strategy Vault! This document provides guidelines and workflows for contributing to this permissionless yield vault protocol.

---

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Project Structure](#project-structure)
- [Contribution Workflow](#contribution-workflow)
- [Coding Standards](#coding-standards)
- [Testing Requirements](#testing-requirements)
- [Security Considerations](#security-considerations)
- [Areas for Contribution](#areas-for-contribution)

---

## Code of Conduct

This project is a learning and demonstration prototype for ERC-4626 vault mechanics. We welcome:

- Educational contributions that improve understanding
- Security research and responsible disclosure
- Gas optimization suggestions
- Strategy implementations for the permissionless marketplace
- Documentation improvements

---

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (latest version)
- Node.js 18+ (for TypeScript utilities)
- Git

### Quick Start

```bash
# Clone the repository
git clone https://github.com/ohMySol/erc4626-strategy-vault.git
cd erc4626-strategy-vault

# Install dependencies
forge install

# Install Node dependencies (for TypeScript utilities)
cd ts && npm install && cd ..

# Run tests
forge test

# Run tests with gas report
forge test --gas-report

# Run tests with coverage
forge coverage
```

---

## Project Structure

```
.
├── src/
│   ├── Vault.sol              # Main ERC-4626 vault implementation
│   ├── VaultFactory.sol       # Factory for deploying vaults
│   ├── BaseStrategy.sol       # Abstract base for strategies
│   ├── interfaces/            # Contract interfaces
│   ├── libraries/             # Utility libraries
│   └── MyToken.sol           # Test token implementation
├── test/                      # Test suite
├── script/                    # Deployment scripts
├── ts/                        # TypeScript utilities
├── lib/                       # Dependencies (forge-std, OpenZeppelin)
└── foundry.toml              # Foundry configuration
```

### Key Components

- **Vault.sol**: Core ERC-4626 vault with timelocks, role-based access, and strategy management
- **BaseStrategy.sol**: Abstract contract for creating yield-generating strategies
- **VaultFactory.sol**: Permissionless vault deployment
- **Timelock Mechanism**: Morpho-style submit/wait/accept flow for critical changes
- **Gasless Deposits**: ERC-2612 permit support for relayer-submitted transactions

---

## Contribution Workflow

### 1. Fork and Branch

```bash
# Fork the repository on GitHub, then:
git clone https://github.com/YOUR_USERNAME/erc4626-strategy-vault.git
cd erc4626-strategy-vault

# Create a feature branch
git checkout -b feature/your-feature-name
```

### 2. Branch Naming Convention

| Type | Pattern | Example |
|------|---------|---------|
| Feature | `feat/description` | `feat/aave-v3-strategy` |
| Bug fix | `fix/description` | `fix/timelock-edge-case` |
| Documentation | `docs/description` | `docs/strategy-guide` |
| Refactor | `refactor/description` | `refactor/vault-storage` |
| Tests | `test/description` | `test/strategy-withdraw` |

### 3. Commit Message Format

```
<type>: <short summary>

<optional longer description>

Co-Authored-By: name <email>
```

Types: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, `security`

Examples:
- `feat: add Compound V3 strategy implementation`
- `fix: correct fee calculation on strategy exit`
- `docs: add strategy development guide`
- `test: add fuzz tests for deposit/withdraw`

### 4. Submit Pull Request

1. Ensure all tests pass: `forge test`
2. Check code formatting: `forge fmt --check`
3. Update documentation if needed
4. Open PR with clear description of changes
5. Link any related issues

---

## Coding Standards

### Solidity Style

- **Version**: Solidity ^0.8.20
- **Style Guide**: Follow [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- **Formatting**: Use `forge fmt` before committing
- **Line Length**: 120 characters maximum
- **Imports**: Group and order: interfaces → libraries → contracts

### Documentation

- All public/external functions must have NatSpec comments
- Complex logic requires inline comments
- Strategy contracts must document:
  - Yield source
  - Risk factors
  - Emergency exit procedure

```solidity
/// @notice Deposits assets into the strategy
/// @param assets The amount of assets to deposit
/// @return shares The amount of strategy shares received
/// @dev Reverts if strategy is paused or cap exceeded
function deposit(uint256 assets) external returns (uint256 shares);
```

### Security Patterns

- Use OpenZeppelin's `ReentrancyGuard` for external calls
- Follow checks-effects-interactions pattern
- Use `SafeERC20` for token transfers
- Validate all inputs with custom errors
- Emit events for all state changes

---

## Testing Requirements

### Test Structure

```
test/
├── Vault.t.sol           # Core vault tests
├── VaultFactory.t.sol    # Factory tests
├── strategies/           # Strategy-specific tests
└── mocks/               # Mock contracts
```

### Test Coverage

- **Minimum 80% coverage** for new code
- All public/external functions must have tests
- Test edge cases and failure modes
- Use fuzzing for input validation: `forge test --fuzz-runs 10000`

### Running Tests

```bash
# Run all tests
forge test

# Run specific test file
forge test --match-path test/Vault.t.sol

# Run with verbosity
forge test -vvv

# Run with gas report
forge test --gas-report

# Run coverage
forge coverage

# Run fuzz tests with high runs
forge test --fuzz-runs 10000
```

### Strategy Testing

When contributing a new strategy:

1. Test deposit/withdraw flows
2. Test yield accrual
3. Test emergency exit
4. Test integration with Vault
5. Document expected APY range and risks

---

## Security Considerations

⚠️ **IMPORTANT**: This is a prototype for educational purposes. It has not been audited.

### For Contributors

- Never commit private keys or `.env` files
- Report security issues privately before public disclosure
- Follow [Solcurity](https://github.com/Rari-Capital/solcurity) checklist
- Consider reentrancy, overflow, and access control in all changes

### For Strategy Developers

- Strategies handle real value - be careful
- Test thoroughly on testnets before mainnet
- Document all external protocol dependencies
- Consider oracle risks, liquidity risks, and smart contract risks
- Implement proper emergency exit mechanisms

### Vulnerability Disclosure

If you discover a security vulnerability:

1. **DO NOT** open a public issue
2. Email the maintainers directly (if contact available)
3. Allow reasonable time for response before public disclosure
4. Follow responsible disclosure practices

---

## Areas for Contribution

### High Priority

1. **Strategy Implementations**
   - Aave V3 strategy
   - Compound V3 strategy
   - Uniswap V3 LP strategy
   - Morpho Blue strategy

2. **Gas Optimizations**
   - Vault deposit/withdraw paths
   - Strategy allocation logic
   - Share calculation math

3. **Testing**
   - Increase test coverage
   - Add invariant tests
   - Add differential tests

### Medium Priority

4. **Documentation**
   - Strategy development guide
   - Architecture diagrams
   - Risk framework documentation

5. **Tooling**
   - Deployment scripts for mainnet
   - Monitoring utilities
   - Strategy performance analytics

### Good First Issues

- Fix typos in documentation
- Add NatSpec to undocumented functions
- Improve error messages
- Add more test cases for edge cases
- Update dependencies to latest versions

---

## Questions?

- Open a [GitHub Discussion](https://github.com/ohMySol/erc4626-strategy-vault/discussions) for questions
- Check existing [Issues](https://github.com/ohMySol/erc4626-strategy-vault/issues) before creating new ones
- Read the [README](./README.md) for project overview

---

## License

By contributing, you agree that your contributions will be licensed under the same license as the project (see repository for specific license).

---

Thank you for contributing to the future of permissionless yield strategies! 🚀