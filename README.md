# KipuBank Smart Contract

A banking smart contract with role-based access control, multi-token support, Chainlink oracle integration, and decimal conversion system.

## Implemented Improvements

### 1. Access Control System
**Implementation:** OpenZeppelin's `AccessControl` with hierarchical roles (ADMIN_ROLE and OPERATOR_ROLE).

**Why:** Provides secure and granular permission management following industry best practices. Enables delegation of operational responsibilities without compromising administrative security.

### 2. Multi-Token Support
**Implementation:** Unified system for ETH and ERC-20 tokens with separate accounting per asset.

**Why:** Increases contract versatility by handling multiple asset types. Uses `address(0)` to represent native ETH, creating a consistent API.

### 3. Chainlink Oracle Integration
**Implementation:** Price feeds for USD conversion, staleness validation, and real value-based limits.

**Why:** Provides more meaningful controls based on actual value instead of volatile quantities. Enables USD-denominated capacity limits, more operationally useful.

### 4. Decimal Conversion System
**Implementation:** Normalization to 6 decimals (USDC standard) with bidirectional conversion functions.

**Why:** Enables precise accounting and comparison across assets with different decimal places (ETH 18, USDC 6, WBTC 8, etc.). Facilitates multi-token portfolio aggregation.

### 5. Security Patterns
**Implementation:** Checks-Effects-Interactions, Pausable, custom errors, and immutable/constant variables.

**Why:** Minimizes attack vectors (reentrancy), optimizes gas costs (~50 gas saved per revert with custom errors), and ensures transparency with comprehensive event emissions.

## Deployment Instructions

### Prerequisites
- Solidity ^0.8.30
- Foundry or Hardhat
- Testnet ETH
- Chainlink price feed addresses

### 1. Compilation
```bash
forge build
```

### 2. Contract Deployment
```solidity
KipuBank bank = new KipuBank(
    1 ether,      // initial withdrawal limit (ETH)
    100 ether     // initial bank capacity (ETH)
);
```

### 3. Configure Price Feed (Optional but Recommended)
```solidity
bank.setPriceFeed(0x694AA1769357215DE4FAC081bf1f309aDC325306);
bank.setBankCapUSD(1_000_000_00000000);
bank.setUseUsdBankCap(true);
```

**Main Price Feeds:**
- Sepolia ETH/USD: `0x694AA1769357215DE4FAC081bf1f309aDC325306`
- Mainnet ETH/USD: `0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419`
- Full list: https://docs.chain.link/data-feeds/price-feeds/addresses

### 4. Add Supported Tokens
```solidity
bank.addSupportedToken(
    0x...,                    // token address (e.g., USDC)
    100_000 * 10**6,          // withdrawal limit
    10_000_000 * 10**6        // max capacity
);

bank.setTokenPriceFeed(0x..., 0x...);
```

## Contract Interaction

### Users

**Deposits:**
```solidity
bank.deposit{value: 1 ether}();

IERC20(token).approve(address(bank), amount);
bank.depositToken(token, amount);
```

**Withdrawals:**
```solidity
bank.withdraw(0.5 ether);
bank.withdrawToken(token, amount);
```

**Queries:**
```solidity
uint256 balance = bank.getTokenVaultBalance(user, address(0));
uint256 totalUSD = bank.getUserTotalValueInUSD(user);
```

### Administrators

**Control:**
```solidity
bank.pause();
bank.unpause();
```

**Token Management:**
```solidity
bank.updateTokenWithdrawalLimit(token, newLimit);
bank.updateTokenBankCap(token, newCap);
bank.removeSupportedToken(token);
```

**Emergency:**
```solidity
bank.emergencyWithdrawToken(token);
```

## Design Decisions and Trade-offs

### 1. Optional USD Bank Cap
**Decision:** USD cap can be enabled/disabled.

**Trade-off:** Adds complexity (+1 boolean flag) but offers operational flexibility. Allows operation without oracles if needed.

### 2. 6-Decimal Normalization
**Decision:** Standardization to 6 decimals (USDC).

**Trade-off:** Precision loss for tokens >6 decimals, but acceptable for financial applications. Balances precision with gas costs and simplicity. Tokens with 18 decimals lose ~12 least significant digits.

### 3. Automatic Decimal Detection
**Decision:** Detect decimals via `IERC20Metadata`, fallback to 18, with manual override.

**Trade-off:** Reduces administrative burden but may fail with non-standard tokens. Solution: `setTokenDecimals()` function enables manual correction when needed.

### 4. ETH as address(0)
**Decision:** Represent native ETH as `address(0)` in unified system.

**Trade-off:** Slightly unconventional pattern but widely adopted. Enables consistent API between ETH and ERC-20s, simplifying business logic.

### 5. Token Whitelist
**Decision:** Admins must explicitly approve each token.

**Trade-off:** Requires administrative action but prevents malicious/incompatible tokens. Avoids contracts with custom transfer logic that could break the system.

### 6. Fee-on-Transfer Tokens
**Decision:** Support fee tokens by calculating `balanceAfter - balanceBefore`.

**Trade-off:** Adds 2 extra storage reads (~2.1k gas) but ensures correct accounting. Essential for tokens like USDT on certain networks.

### 7. Checks-Effects-Interactions
**Decision:** Always update state before external calls.

**Trade-off:** May require more verbose logic but prevents reentrancy. Minimal additional cost in code organization, massive security benefit.

## Security

**Implemented Patterns:**
- ✅ Checks-Effects-Interactions (prevents reentrancy)
- ✅ Access Control (OpenZeppelin)
- ✅ Pausable (emergency stop)
- ✅ Oracle staleness validation (max 1 hour)
- ✅ Custom errors (gas efficiency)
- ✅ Token whitelist

**Known Limitations:**
1. Removing token support locks user funds until reactivation
2. Normalization may lose precision for tokens >6 decimals
3. USD features depend on functional Chainlink feeds
4. No yield/interest generation (future version)

## Project Structure

```
src/
├── KipuBank.sol                          # Main contract (596 lines)
└── interfaces/
    └── AggregatorV3Interface.sol         # Chainlink interface

lib/openzeppelin-contracts/               # OpenZeppelin dependencies
foundry.toml                              # Foundry configuration
remappings.txt                            # Import mappings
```

## Testing

```bash
forge test -vvv
```

## Gas Optimizations

- Custom errors (~50 gas saved per revert)
- `constant` for role identifiers
- `immutable` for owner
- Nested mappings (O(1) lookups)
- Early validations (fail fast)

## License

MIT