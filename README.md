# KipuBankV2 Smart Contract

An banking smart contract with role-based access control, multi-token support, Chainlink oracle integration, and decimal conversion system.

## Overview

KipuBankV2 is an evolution of the original KipuBank contract, implementing production-ready features including:

- **Role-Based Access Control** using OpenZeppelin contracts
- **Multi-Token Support** for ETH and ERC-20 tokens
- **Unified Accounting System** with normalized decimal handling
- **Chainlink Price Feeds** for real-time USD valuations
- **Decimal Conversion** standardized to USDC (6 decimals)
- **Security Patterns** including checks-effects-interactions and pausability

## Key Improvements from V1

### 1. Access Control System
Implemented OpenZeppelin's `AccessControl` with two main roles:

- **ADMIN_ROLE**: Full administrative privileges (pause, update limits, manage tokens, emergency withdrawals)
- **OPERATOR_ROLE**: Reserved for future operational features

Role hierarchy:
```
DEFAULT_ADMIN_ROLE (root)
    └── ADMIN_ROLE
            └── OPERATOR_ROLE
```

**Why?** Provides secure, granular permission management following industry best practices.

### 2. Multi-Token Support
Extended beyond native ETH to support any ERC-20 token:

- Unified accounting using `address(0)` for ETH
- Independent withdrawal limits and bank caps per token
- Token whitelist managed by admins
- Support for fee-on-transfer tokens
- Automatic decimal detection via `IERC20Metadata`

**Why?** Enables the bank to handle multiple asset types, increasing versatility and real-world applicability.

### 3. Chainlink Oracle Integration
Real-time price data for USD-based controls:

- ETH/USD price feed integration
- Bank capacity limits in USD (not just native units)
- Price staleness validation
- Multi-token price feed support
- Toggle USD-based controls on/off

**Why?** Provides more meaningful limits based on actual value rather than volatile token amounts.

### 4. Decimal Conversion System
Standardized handling of different token decimals:

- Normalization to 6 decimals (USDC standard)
- Bidirectional conversion functions
- Portfolio value aggregation in USD
- Cross-token balance comparisons

**Why?** Enables accurate accounting and comparison across assets with different decimal places (ETH 18, USDC 6, WBTC 8, etc.).

### 5. Security & Efficiency
Multiple security patterns and gas optimizations:

- **Checks-Effects-Interactions** pattern in all state-changing functions
- **Pausable** emergency stop mechanism
- **Custom errors** for gas-efficient reverts
- **Immutable** variables where applicable
- **Constants** for role identifiers and fixed values
- Comprehensive event emissions for transparency

**Why?** Follows Solidity best practices to minimize attack vectors and optimize gas costs.

## Architecture

### Type Declarations
```solidity
// Role identifiers (constant for gas efficiency)
bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

// Decimal management constants
uint8 public constant NORMALIZED_DECIMALS = 6;  // USDC standard
uint8 public constant ETH_DECIMALS = 18;

// Immutable owner set at deployment
address public immutable owner;
```

### Nested Mappings for Unified Accounting
```solidity
// Core accounting: user => token => balance
mapping(address => mapping(address => uint256)) private _vaults;

// Token metadata
mapping(address => uint8) private _tokenDecimals;
mapping(address => uint256) private _withdrawalLimits;
mapping(address => uint256) private _bankCaps;
mapping(address => bool) private _supportedTokens;

// Chainlink price feeds per token
mapping(address => AggregatorV3Interface) private _tokenPriceFeeds;
```

### Chainlink Oracle Instance
```solidity
// ETH/USD price feed
AggregatorV3Interface public ethUsdPriceFeed;

// USD-denominated bank cap (8 decimals)
uint256 public bankCapUSD;

// Maximum acceptable price age (default: 1 hour)
uint256 public maxPriceAge = 1 hours;
```

### Custom Errors
```solidity
error ZeroAmount();
error ZeroBankCap();
error ZeroWithdrawalLimit();
error BankCapacityExceeded();
error WithdrawalLimitExceeded();
error InsufficientVaultBalance();
error TransferFailed();
error ZeroAddress();
error TokenNotSupported();
error TokenAlreadySupported();
error ERC20TransferFailed();
error StalePrice();
error InvalidPrice();
error InvalidDecimals();
```

## Core Functions

### User Operations

**ETH Deposits/Withdrawals:**
```solidity
function deposit() external payable whenNotPaused;
function withdraw(uint256 amount) external validAmount(amount) whenNotPaused;
```

**ERC-20 Deposits/Withdrawals:**
```solidity
function depositToken(address token, uint256 amount) external payable whenNotPaused;
function withdrawToken(address token, uint256 amount) external whenNotPaused;
```

**Balance Queries:**
```solidity
function getTokenVaultBalance(address user, address token) external view returns (uint256);
function getMyTokenVaultBalance(address token) external view returns (uint256);
```

### Decimal Conversion Functions

**Convert to/from normalized decimals:**
```solidity
function convertToNormalizedDecimals(address token, uint256 amount) public view returns (uint256);
function convertFromNormalizedDecimals(address token, uint256 normalizedAmount) public view returns (uint256);
```

**Example Usage:**
```solidity
// Convert 1 ETH (18 decimals) to normalized (6 decimals)
uint256 ethAmount = 1 ether;  // 1e18
uint256 normalized = convertToNormalizedDecimals(address(0), ethAmount);
// Result: 1e6

// Get normalized balance for comparison
uint256 ethBalance = getTokenVaultBalanceNormalized(user, address(0));
uint256 usdcBalance = getTokenVaultBalanceNormalized(user, usdcToken);
// Now comparable: ethBalance vs usdcBalance
```

### Price Feed & USD Conversion

**Get current prices:**
```solidity
function getLatestEthPrice() public view returns (uint256);
function getTokenPrice(address token) public view returns (uint256);
```

**Convert to USD:**
```solidity
function convertEthToUSD(uint256 ethAmount) public view returns (uint256);
function convertTokenToUSD(address token, uint256 amount) public view returns (uint256);
function getUserTotalValueInUSD(address user) external view returns (uint256);
```

### Administrative Functions (ADMIN_ROLE only)

**Contract control:**
```solidity
function pause() external onlyRole(ADMIN_ROLE);
function unpause() external onlyRole(ADMIN_ROLE);
```

**Token management:**
```solidity
function addSupportedToken(address token, uint256 withdrawalLimit, uint256 bankCap) external;
function removeSupportedToken(address token) external;
function updateTokenWithdrawalLimit(address token, uint256 newLimit) external;
function updateTokenBankCap(address token, uint256 newCap) external;
```

**Oracle configuration:**
```solidity
function setPriceFeed(address priceFeedAddress) external;
function setTokenPriceFeed(address token, address priceFeedAddress) external;
function setBankCapUSD(uint256 newBankCapUSD) external;
function setUseUsdBankCap(bool enabled) external;
function setMaxPriceAge(uint256 newMaxAge) external;
```

**Emergency functions:**
```solidity
function emergencyWithdraw() external;
function emergencyWithdrawToken(address token) external;
```

## Deployment Instructions

### Prerequisites
- Solidity ^0.8.30
- Foundry or Hardhat
- Testnet ETH (for deployment)
- Chainlink price feed addresses for your network

### Compilation

**Using Foundry:**
```bash
forge build
```

**Using Hardhat:**
```bash
npx hardhat compile
```

### Deployment Steps

1. **Deploy the contract** with initial ETH parameters:
```solidity
// Example: 1 ETH withdrawal limit, 100 ETH capacity
KipuBank bank = new KipuBank(1 ether, 100 ether);
```

2. **Configure Chainlink price feed** (example for Sepolia):
```solidity
// Sepolia ETH/USD: 0x694AA1769357215DE4FAC081bf1f309aDC325306
bank.setPriceFeed(0x694AA1769357215DE4FAC081bf1f309aDC325306);
```

3. **Set USD bank cap** (optional):
```solidity
// $1,000,000 USD cap (8 decimals)
bank.setBankCapUSD(1_000_000_00000000);
bank.setUseUsdBankCap(true);
```

4. **Add supported ERC-20 tokens**:
```solidity
// Example: Add USDC with 100,000 USDC withdrawal limit and 10M cap
address usdcToken = 0x...; // USDC address on your network
bank.addSupportedToken(
    usdcToken,
    100_000 * 10**6,  // 100k USDC (6 decimals)
    10_000_000 * 10**6 // 10M USDC cap
);

// Set USDC price feed if needed
bank.setTokenPriceFeed(usdcToken, 0x...); // USDC/USD feed address
```

### Network-Specific Price Feed Addresses

**Ethereum Mainnet:**
- ETH/USD: `0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419`
- BTC/USD: `0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c`
- USDC/USD: `0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6`

**Sepolia Testnet:**
- ETH/USD: `0x694AA1769357215DE4FAC081bf1f309aDC325306`
- BTC/USD: `0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43`
- USDC/USD: `0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E`

**Arbitrum:**
- ETH/USD: `0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612`
- BTC/USD: `0x6ce185860a4963106506C203335A2910413708e9`

Find more feeds at: https://docs.chain.link/data-feeds/price-feeds/addresses

## Interaction Examples

### User Deposits
```solidity
// Deposit ETH
bank.deposit{value: 1 ether}();

// Approve and deposit USDC
IERC20(usdcToken).approve(address(bank), 1000 * 10**6);
bank.depositToken(usdcToken, 1000 * 10**6);
```

### User Withdrawals
```solidity
// Withdraw 0.5 ETH
bank.withdraw(0.5 ether);

// Withdraw 500 USDC
bank.withdrawToken(usdcToken, 500 * 10**6);
```

### Query Balances
```solidity
// Get ETH balance
uint256 ethBal = bank.getTokenVaultBalance(user, address(0));

// Get USDC balance
uint256 usdcBal = bank.getTokenVaultBalance(user, usdcToken);

// Get total value in USD
uint256 totalUSD = bank.getUserTotalValueInUSD(user);
```

### Admin Operations
```solidity
// Pause in emergency
bank.pause();

// Update ETH withdrawal limit to 2 ETH
bank.updateTokenWithdrawalLimit(address(0), 2 ether);

// Grant operator role
bank.addOperator(operatorAddress);
```

## Security Considerations

### Implemented Security Patterns

1. **Checks-Effects-Interactions**
   - All state changes occur before external calls
   - Prevents reentrancy attacks
   - Example: `withdraw()` updates balance before transferring ETH

2. **Access Control**
   - Role-based permissions using OpenZeppelin
   - Principle of least privilege
   - Admin functions protected by `onlyRole` modifier

3. **Pausability**
   - Emergency stop mechanism
   - Admins can halt deposits/withdrawals if needed
   - Maintains contract integrity during incidents

4. **Input Validation**
   - Custom errors for invalid inputs
   - Zero address checks
   - Amount validation
   - Token whitelist enforcement

5. **Oracle Safety**
   - Price staleness validation (default 1 hour max age)
   - Round completeness checks
   - Invalid price detection
   - Graceful degradation if feed unavailable

### Design Trade-offs

**1. USD Bank Cap Toggle**
- **Decision**: Made USD cap optional (can be enabled/disabled)
- **Rationale**: Provides flexibility for different operational modes
- **Trade-off**: Adds complexity but increases control

**2. Decimal Normalization to 6**
- **Decision**: Chose USDC's 6 decimals as standard
- **Rationale**: USDC is widely adopted and 6 decimals balances precision with gas costs
- **Trade-off**: Some precision loss for tokens with >6 decimals, but acceptable for financial applications

**3. Automatic Decimal Detection**
- **Decision**: Auto-detect decimals via `IERC20Metadata`, fallback to 18
- **Rationale**: Reduces admin burden, works with standard tokens
- **Trade-off**: May fail with non-standard tokens, but admin can override with `setTokenDecimals()`

**4. Native ETH via address(0)**
- **Decision**: Represent ETH as `address(0)` in unified system
- **Rationale**: Enables consistent API for both ETH and ERC-20s
- **Trade-off**: Slightly unconventional but widely used pattern

**5. Token Whitelist**
- **Decision**: Admins must explicitly approve each token
- **Rationale**: Prevents malicious/incompatible tokens from being used
- **Trade-off**: Requires admin action but significantly improves security

## Testing

The contract includes comprehensive test files:

- `TestCompile.sol` - Basic compilation and deployment tests
- `TestChainlink.sol` - Oracle integration and price feed tests
- `TestConversaoDecimais.sol` - Decimal conversion system tests

Run tests with Foundry:
```bash
forge test -vvv
```

## Project Structure

```
.
├── KipuBank.sol                      # Main contract (917 lines)
├── openzeppelin/                     # OpenZeppelin contracts (local)
│   ├── access/
│   │   ├── AccessControl.sol
│   │   └── IAccessControl.sol
│   ├── interfaces/
│   │   ├── AggregatorV3Interface.sol # Chainlink interface
│   │   └── IERC165.sol
│   ├── token/
│   │   ├── IERC20.sol
│   │   └── IERC20Metadata.sol
│   └── utils/
│       ├── Context.sol
│       ├── ERC165.sol
│       ├── Pausable.sol
│       └── ReentrancyGuard.sol
├── TestChainlink.sol                 # Chainlink tests
├── TestCompile.sol                   # Basic tests
├── TestConversaoDecimais.sol         # Decimal conversion tests
├── foundry.toml                      # Foundry config
├── remappings.txt                    # Import remappings
└── README.md                         # This file
```

## Events

The contract emits comprehensive events for all operations:

**ETH Operations:**
```solidity
event Deposit(address indexed user, uint256 amount, uint256 newBalance);
event Withdrawal(address indexed user, uint256 amount, uint256 newBalance);
event WithdrawalLimitUpdated(uint256 oldLimit, uint256 newLimit);
event BankCapUpdated(uint256 oldCap, uint256 newCap);
event EmergencyWithdrawal(address indexed admin, uint256 amount);
```

**ERC-20 Operations:**
```solidity
event TokenDeposit(address indexed user, address indexed token, uint256 amount, uint256 newBalance);
event TokenWithdrawal(address indexed user, address indexed token, uint256 amount, uint256 newBalance);
event TokenAdded(address indexed token, uint256 withdrawalLimit, uint256 bankCap);
event TokenRemoved(address indexed token);
event TokenWithdrawalLimitUpdated(address indexed token, uint256 oldLimit, uint256 newLimit);
event TokenBankCapUpdated(address indexed token, uint256 oldCap, uint256 newCap);
event TokenEmergencyWithdrawal(address indexed admin, address indexed token, uint256 amount);
```

**Oracle Events:**
```solidity
event PriceFeedUpdated(address indexed oldPriceFeed, address indexed newPriceFeed);
event BankCapUSDUpdated(uint256 oldCap, uint256 newCap);
event MaxPriceAgeUpdated(uint256 oldAge, uint256 newAge);
event UsdBankCapToggled(bool enabled);
event TokenPriceFeedSet(address indexed token, address indexed priceFeed);
```

## Gas Optimizations

- Custom errors instead of revert strings (saves ~50 gas per revert)
- `constant` for role identifiers (saves storage reads)
- `immutable` for owner (set once at construction)
- Efficient nested mappings (O(1) lookups)
- Cached array length in loops
- Early validation to fail fast

## Known Limitations

1. **Token Removal**: Removing token support locks user funds until token is re-added
2. **Fee-on-Transfer**: Handled but adds complexity
3. **Decimal Precision**: Normalization to 6 decimals may lose precision for tokens >6 decimals
4. **Oracle Dependency**: USD features require functional Chainlink feeds
5. **No Yield**: Deposited funds don't earn interest (feature for future versions)

## Deployed Contract

**Network**: [Your testnet - e.g., Sepolia]  
**Contract Address**: [Your deployed contract address]  
**Explorer**: [Link to verified contract on block explorer]

## Future Improvements

Potential enhancements for future versions:
- Interest-bearing deposits
- Lending/borrowing functionality
- Cross-chain bridge support
- Governance token integration
- Yield farming strategies
- Flash loan capabilities

## License

MIT

---

**Built with ❤️ using Solidity, OpenZeppelin, and Chainlink**