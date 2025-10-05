# KipuBank

Banking smart contract with role-based access control, multi-token support, and Chainlink oracle integration.

## Features

- Deposits and withdrawals for ETH and ERC-20 tokens
- Permission system with roles (ADMIN and OPERATOR)
- Chainlink integration for USD conversion
- Decimal normalization for cross-token comparisons
- Pausable for emergencies
- Supports fee-on-transfer tokens

## Deploy

```bash
forge build
forge create src/KipuBank.sol:KipuBank --constructor-args 1000000000000000000 100000000000000000000
```

Setup oracle (optional):
```solidity
bank.setPriceFeed(0x694AA1769357215DE4FAC081bf1f309aDC325306); // Sepolia ETH/USD
bank.setBankCapUSD(1_000_000_00000000);
bank.setUseUsdBankCap(true);
```

Add tokens:
```solidity
bank.addSupportedToken(tokenAddress, withdrawalLimit, maxCap);
bank.setTokenPriceFeed(tokenAddress, priceFeedAddress);
```

## Usage

Deposit:
```solidity
bank.deposit{value: 1 ether}();
// or
token.approve(address(bank), amount);
bank.depositToken(token, amount);
```

Withdraw:
```solidity
bank.withdraw(0.5 ether);
bank.withdrawToken(token, amount);
```

Admin:
```solidity
bank.pause(); // emergency
bank.updateTokenWithdrawalLimit(token, newLimit);
bank.emergencyWithdrawToken(token); // recover funds
```

## Technical Notes

- ETH is represented as `address(0)` internally
- Normalization to 6 decimals (USDC standard) for comparisons
- Fee-on-transfer token support using balance diff
- CEI pattern to prevent reentrancy
- Oracle staleness check: max 1 hour

**Known limitations:**
- Removing token support locks user funds until reactivated
- Precision loss for tokens with >6 decimals
- USD features depend on Chainlink working properly

## Structure

```
src/
├── KipuBank.sol
└── interfaces/
    └── AggregatorV3Interface.sol
```

## Testing

```bash
forge test -vvv
```

## License

MIT