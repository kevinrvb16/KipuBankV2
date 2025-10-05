// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";

contract KipuBank is AccessControl, Pausable {

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // Custom errors q economizam gas
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

    // user => token => balance
    mapping(address => mapping(address => uint256)) private _vaults;
    mapping(address => uint256) private _totalDeposits;
    mapping(address => uint256) private _withdrawalLimits;
    mapping(address => uint256) private _bankCaps;
    mapping(address => bool) private _supportedTokens;
    address[] private _tokenList;
    
    uint8 public constant NORMALIZED_DECIMALS = 6;
    uint8 public constant ETH_DECIMALS = 18;
    mapping(address => uint8) private _tokenDecimals;
    mapping(address => AggregatorV3Interface) private _tokenPriceFeeds;
    
    address public immutable owner;
    uint256 public totalWithdrawals;

    AggregatorV3Interface public ethUsdPriceFeed;
    uint256 public bankCapUSD;
    uint256 public maxPriceAge = 1 hours;
    bool public useUsdBankCap;

    event Deposit(address indexed user, uint256 amount, uint256 newBalance);
    event Withdrawal(address indexed user, uint256 amount, uint256 newBalance);
    event WithdrawalLimitUpdated(uint256 oldLimit, uint256 newLimit);
    event BankCapUpdated(uint256 oldCap, uint256 newCap);
    event EmergencyWithdrawal(address indexed admin, uint256 amount);

    event TokenDeposit(address indexed user, address indexed token, uint256 amount, uint256 newBalance);
    event TokenWithdrawal(address indexed user, address indexed token, uint256 amount, uint256 newBalance);
    event TokenAdded(address indexed token, uint256 withdrawalLimit, uint256 bankCap);
    event TokenRemoved(address indexed token);
    event TokenWithdrawalLimitUpdated(address indexed token, uint256 oldLimit, uint256 newLimit);
    event TokenBankCapUpdated(address indexed token, uint256 oldCap, uint256 newCap);
    event TokenEmergencyWithdrawal(address indexed admin, address indexed token, uint256 amount);

    event PriceFeedUpdated(address indexed oldPriceFeed, address indexed newPriceFeed);
    event BankCapUSDUpdated(uint256 oldCap, uint256 newCap);
    event MaxPriceAgeUpdated(uint256 oldAge, uint256 newAge);
    event UsdBankCapToggled(bool enabled);
    
    event TokenDecimalsUpdated(address indexed token, uint8 oldDecimals, uint8 newDecimals);
    event TokenPriceFeedSet(address indexed token, address indexed priceFeed);

    constructor(uint256 _maxWithdrawalLimit, uint256 _bankCap) {
        if (_bankCap == 0) revert ZeroBankCap();
        if (_maxWithdrawalLimit == 0) revert ZeroWithdrawalLimit();
        
        owner = msg.sender;
        totalWithdrawals = 0;

        _supportedTokens[address(0)] = true;
        _withdrawalLimits[address(0)] = _maxWithdrawalLimit;
        _bankCaps[address(0)] = _bankCap;
        _tokenDecimals[address(0)] = ETH_DECIMALS;
        _tokenList.push(address(0));

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);
    }

    modifier validAmount(uint256 amount) {
        if (amount == 0) revert ZeroAmount();
        _;
    }

    function deposit() external payable whenNotPaused {
        if (msg.value == 0) revert ZeroAmount();
        
        address token = address(0);
        
        if (address(this).balance > _bankCaps[token]) revert BankCapacityExceeded();
        
        // Checar limit USD se ativado
        if (useUsdBankCap && address(ethUsdPriceFeed) != address(0)) {
            uint256 bankValueUSD = getContractValueInUSD();
            if (bankValueUSD > bankCapUSD) revert BankCapacityExceeded();
        }
        
        _vaults[msg.sender][token] += msg.value;
        _totalDeposits[token]++;
        
        emit Deposit(msg.sender, msg.value, _vaults[msg.sender][token]);
    }

    function getVaultBalance(address user) external view returns (uint256) {
        return _vaults[user][address(0)];
    }
    
    function getMyVaultBalance() external view returns (uint256) {
        return _vaults[msg.sender][address(0)];
    }
    
    function getMaxWithdrawalLimit() external view returns (uint256) {
        return _withdrawalLimits[address(0)];
    }
    
    function getBankCap() external view returns (uint256) {
        return _bankCaps[address(0)];
    }
    
    function getTotalDeposits() external view returns (uint256) {
        return _totalDeposits[address(0)];
    }
    
    function getTotalWithdrawals() external view returns (uint256) {
        return totalWithdrawals;
    }

    function withdraw(uint256 amount) external validAmount(amount) whenNotPaused {
        address token = address(0);
        
        if (amount > _withdrawalLimits[token]) revert WithdrawalLimitExceeded();
        if (_vaults[msg.sender][token] < amount) revert InsufficientVaultBalance();
        
        _vaults[msg.sender][token] -= amount;
        totalWithdrawals++;
        
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        if (!success) revert TransferFailed();
        
        emit Withdrawal(msg.sender, amount, _vaults[msg.sender][token]);
    }

    function depositToken(address token, uint256 amount) external payable validAmount(amount) whenNotPaused {
        if (token == address(0)) revert TokenNotSupported();
        if (!_supportedTokens[token]) revert TokenNotSupported();
        
        // Suporte a fee-on-transfer tokens - usar balance diff
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        
        bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
        if (!success) revert ERC20TransferFailed();
        
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));
        uint256 actualAmount = balanceAfter - balanceBefore;
        
        if (balanceAfter > _bankCaps[token]) revert BankCapacityExceeded();
        
        _vaults[msg.sender][token] += actualAmount;
        _totalDeposits[token]++;
        
        emit TokenDeposit(msg.sender, token, actualAmount, _vaults[msg.sender][token]);
    }

    function withdrawToken(address token, uint256 amount) external validAmount(amount) whenNotPaused {
        if (token == address(0)) revert TokenNotSupported();
        if (!_supportedTokens[token]) revert TokenNotSupported();
        if (amount > _withdrawalLimits[token]) revert WithdrawalLimitExceeded();
        if (_vaults[msg.sender][token] < amount) revert InsufficientVaultBalance();
        
        _vaults[msg.sender][token] -= amount;
        
        bool success = IERC20(token).transfer(msg.sender, amount);
        if (!success) revert ERC20TransferFailed();
        
        emit TokenWithdrawal(msg.sender, token, amount, _vaults[msg.sender][token]);
    }

    function getTokenVaultBalance(address user, address token) external view returns (uint256) {
        return _vaults[user][token];
    }

    function getMyTokenVaultBalance(address token) external view returns (uint256) {
        return _vaults[msg.sender][token];
    }

    function isTokenSupported(address token) external view returns (bool) {
        return _supportedTokens[token];
    }

    function getTokenWithdrawalLimit(address token) external view returns (uint256) {
        return _withdrawalLimits[token];
    }

    function getTokenBankCap(address token) external view returns (uint256) {
        return _bankCaps[token];
    }

    function getTokenTotalDeposits(address token) external view returns (uint256) {
        return _totalDeposits[token];
    }

    function getSupportedTokens() external view returns (address[] memory) {
        return _tokenList;
    }

    function getTokenContractBalance(address token) external view returns (uint256) {
        if (token == address(0)) {
            return address(this).balance;
        }
        return IERC20(token).balanceOf(address(this));
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    function updateWithdrawalLimit(uint256 newLimit) external onlyRole(ADMIN_ROLE) {
        if (newLimit == 0) revert ZeroWithdrawalLimit();
        uint256 oldLimit = _withdrawalLimits[address(0)];
        _withdrawalLimits[address(0)] = newLimit;
        emit WithdrawalLimitUpdated(oldLimit, newLimit);
    }

    function updateBankCap(uint256 newCap) external onlyRole(ADMIN_ROLE) {
        if (newCap == 0) revert ZeroBankCap();
        uint256 oldCap = _bankCaps[address(0)];
        _bankCaps[address(0)] = newCap;
        emit BankCapUpdated(oldCap, newCap);
    }

    function emergencyWithdraw() external onlyRole(ADMIN_ROLE) {
        uint256 balance = address(this).balance;
        if (balance == 0) revert ZeroAmount();
        
        (bool success, ) = payable(msg.sender).call{value: balance}("");
        if (!success) revert TransferFailed();
        
        emit EmergencyWithdrawal(msg.sender, balance);
    }

    function addOperator(address operator) external onlyRole(ADMIN_ROLE) {
        if (operator == address(0)) revert ZeroAddress();
        grantRole(OPERATOR_ROLE, operator);
    }

    function removeOperator(address operator) external onlyRole(ADMIN_ROLE) {
        if (operator == address(0)) revert ZeroAddress();
        revokeRole(OPERATOR_ROLE, operator);
    }

    function isAdmin(address account) external view returns (bool) {
        return hasRole(ADMIN_ROLE, account);
    }

    function isOperator(address account) external view returns (bool) {
        return hasRole(OPERATOR_ROLE, account);
    }

    function addSupportedToken(
        address token,
        uint256 withdrawalLimit,
        uint256 tokenBankCap
    ) external onlyRole(ADMIN_ROLE) {
        if (token == address(0)) revert ZeroAddress();
        if (_supportedTokens[token]) revert TokenAlreadySupported();
        if (withdrawalLimit == 0) revert ZeroWithdrawalLimit();
        if (tokenBankCap == 0) revert ZeroBankCap();
        
        _supportedTokens[token] = true;
        _withdrawalLimits[token] = withdrawalLimit;
        _bankCaps[token] = tokenBankCap;
        _tokenList.push(token);
        
        // Tentar pegar decimals automaticamente, fallback pra 18
        try IERC20Metadata(token).decimals() returns (uint8 decimals) {
            _tokenDecimals[token] = decimals;
        } catch {
            _tokenDecimals[token] = 18;
        }
        
        emit TokenAdded(token, withdrawalLimit, tokenBankCap);
    }

    function removeSupportedToken(address token) external onlyRole(ADMIN_ROLE) {
        if (token == address(0)) revert ZeroAddress();
        if (!_supportedTokens[token]) revert TokenNotSupported();
        
        // TODO: considerar check se tem saldo de users antes de remover?
        _supportedTokens[token] = false;
        
        for (uint256 i = 0; i < _tokenList.length; i++) {
            if (_tokenList[i] == token) {
                _tokenList[i] = _tokenList[_tokenList.length - 1];
                _tokenList.pop();
                break;
            }
        }
        
        emit TokenRemoved(token);
    }

    function updateTokenWithdrawalLimit(
        address token,
        uint256 newLimit
    ) external onlyRole(ADMIN_ROLE) {
        if (!_supportedTokens[token]) revert TokenNotSupported();
        if (newLimit == 0) revert ZeroWithdrawalLimit();
        
        uint256 oldLimit = _withdrawalLimits[token];
        _withdrawalLimits[token] = newLimit;
        
        emit TokenWithdrawalLimitUpdated(token, oldLimit, newLimit);
    }

    function updateTokenBankCap(
        address token,
        uint256 newCap
    ) external onlyRole(ADMIN_ROLE) {
        if (!_supportedTokens[token]) revert TokenNotSupported();
        if (newCap == 0) revert ZeroBankCap();
        
        uint256 oldCap = _bankCaps[token];
        _bankCaps[token] = newCap;
        
        emit TokenBankCapUpdated(token, oldCap, newCap);
    }

    function emergencyWithdrawToken(address token) external onlyRole(ADMIN_ROLE) {
        uint256 balance;
        
        if (token == address(0)) {
            balance = address(this).balance;
            if (balance == 0) revert ZeroAmount();
            
            (bool success, ) = payable(msg.sender).call{value: balance}("");
            if (!success) revert TransferFailed();
        } else {
            balance = IERC20(token).balanceOf(address(this));
            if (balance == 0) revert ZeroAmount();
            
            bool success = IERC20(token).transfer(msg.sender, balance);
            if (!success) revert ERC20TransferFailed();
        }
        
        emit TokenEmergencyWithdrawal(msg.sender, token, balance);
    }

    function getLatestEthPrice() public view returns (uint256) {
        if (address(ethUsdPriceFeed) == address(0)) revert ZeroAddress();
        
        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = ethUsdPriceFeed.latestRoundData();
        
        // Validar que price feed não está stale (padrão: 1h)
        if (updatedAt == 0 || block.timestamp - updatedAt > maxPriceAge) {
            revert StalePrice();
        }
        
        if (answer <= 0) revert InvalidPrice();
        
        if (answeredInRound < roundId) revert StalePrice();
        
        return uint256(answer);
    }

    function convertEthToUSD(uint256 ethAmount) public view returns (uint256) {
        if (address(ethUsdPriceFeed) == address(0)) {
            return 0;
        }
        
        uint256 ethPrice = getLatestEthPrice();
        
        return (ethAmount * ethPrice) / 1e18;
    }

    function getContractValueInUSD() public view returns (uint256) {
        return convertEthToUSD(address(this).balance);
    }

    function getUserVaultBalanceInUSD(address user) external view returns (uint256) {
        return convertEthToUSD(_vaults[user][address(0)]);
    }

    function setPriceFeed(address priceFeedAddress) external onlyRole(ADMIN_ROLE) {
        if (priceFeedAddress == address(0)) revert ZeroAddress();
        
        address oldPriceFeed = address(ethUsdPriceFeed);
        ethUsdPriceFeed = AggregatorV3Interface(priceFeedAddress);
        
        emit PriceFeedUpdated(oldPriceFeed, priceFeedAddress);
    }

    function setBankCapUSD(uint256 newBankCapUSD) external onlyRole(ADMIN_ROLE) {
        if (newBankCapUSD == 0) revert ZeroBankCap();
        
        uint256 oldCap = bankCapUSD;
        bankCapUSD = newBankCapUSD;
        
        emit BankCapUSDUpdated(oldCap, newBankCapUSD);
    }

    function setMaxPriceAge(uint256 newMaxAge) external onlyRole(ADMIN_ROLE) {
        if (newMaxAge == 0) revert ZeroAmount();
        
        uint256 oldAge = maxPriceAge;
        maxPriceAge = newMaxAge;
        
        emit MaxPriceAgeUpdated(oldAge, newMaxAge);
    }

    function setUseUsdBankCap(bool enabled) external onlyRole(ADMIN_ROLE) {
        useUsdBankCap = enabled;
        emit UsdBankCapToggled(enabled);
    }

    function isPriceFeedValid() external view returns (bool isValid, uint256 currentPrice) {
        if (address(ethUsdPriceFeed) == address(0)) {
            return (false, 0);
        }
        
        try this.getLatestEthPrice() returns (uint256 price) {
            return (true, price);
        } catch {
            return (false, 0);
        }
    }

    function getTokenDecimals(address token) public view returns (uint8) {
        return _tokenDecimals[token];
    }

    function convertToNormalizedDecimals(address token, uint256 amount) public view returns (uint256) {
        uint8 tokenDecimals = _tokenDecimals[token];
        
        if (tokenDecimals == 0) revert TokenNotSupported();
        
        if (tokenDecimals == NORMALIZED_DECIMALS) {
            return amount;
        } else if (tokenDecimals > NORMALIZED_DECIMALS) {
            uint8 decimalDiff = tokenDecimals - NORMALIZED_DECIMALS;
            return amount / (10 ** decimalDiff);
        } else {
            uint8 decimalDiff = NORMALIZED_DECIMALS - tokenDecimals;
            return amount * (10 ** decimalDiff);
        }
    }

    function convertFromNormalizedDecimals(address token, uint256 normalizedAmount) public view returns (uint256) {
        uint8 tokenDecimals = _tokenDecimals[token];
        
        if (tokenDecimals == 0) revert TokenNotSupported();
        
        if (tokenDecimals == NORMALIZED_DECIMALS) {
            return normalizedAmount;
        } else if (tokenDecimals > NORMALIZED_DECIMALS) {
            uint8 decimalDiff = tokenDecimals - NORMALIZED_DECIMALS;
            return normalizedAmount * (10 ** decimalDiff);
        } else {
            uint8 decimalDiff = NORMALIZED_DECIMALS - tokenDecimals;
            return normalizedAmount / (10 ** decimalDiff);
        }
    }

    function getTokenVaultBalanceNormalized(address user, address token) external view returns (uint256) {
        uint256 balance = _vaults[user][token];
        return convertToNormalizedDecimals(token, balance);
    }

    function getTokenPrice(address token) public view returns (uint256) {
        AggregatorV3Interface priceFeed;
        
        if (token == address(0)) {
            if (address(ethUsdPriceFeed) == address(0)) return 0;
            priceFeed = ethUsdPriceFeed;
        } else {
            if (address(_tokenPriceFeeds[token]) == address(0)) return 0;
            priceFeed = _tokenPriceFeeds[token];
        }
        
        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        
        if (updatedAt == 0 || block.timestamp - updatedAt > maxPriceAge) {
            revert StalePrice();
        }
        
        if (answer <= 0) revert InvalidPrice();
        
        if (answeredInRound < roundId) revert StalePrice();
        
        return uint256(answer);
    }

    function convertTokenToUSD(address token, uint256 amount) public view returns (uint256) {
        if (address(_tokenPriceFeeds[token]) == address(0) && token != address(0)) {
            return 0;
        }
        
        if (token == address(0) && address(ethUsdPriceFeed) == address(0)) {
            return 0;
        }
        
        uint256 tokenPrice = getTokenPrice(token);
        uint8 tokenDecimals = _tokenDecimals[token];
        
        return (amount * tokenPrice) / (10 ** tokenDecimals);
    }

    function getUserTokenBalanceInUSD(address user, address token) external view returns (uint256) {
        uint256 balance = _vaults[user][token];
        return convertTokenToUSD(token, balance);
    }

    function getUserTotalValueInUSD(address user) external view returns (uint256) {
        uint256 totalValue = 0;
        
        for (uint256 i = 0; i < _tokenList.length; i++) {
            address token = _tokenList[i];
            uint256 balance = _vaults[user][token];
            
            if (balance > 0) {
                uint256 tokenValueUSD = convertTokenToUSD(token, balance);
                totalValue += tokenValueUSD;
            }
        }
        
        return totalValue;
    }

    function getTotalContractValueInUSD() external view returns (uint256) {
        uint256 totalValue = 0;
        
        for (uint256 i = 0; i < _tokenList.length; i++) {
            address token = _tokenList[i];
            uint256 balance;
            
            if (token == address(0)) {
                balance = address(this).balance;
            } else {
                balance = IERC20(token).balanceOf(address(this));
            }
            
            if (balance > 0) {
                uint256 tokenValueUSD = convertTokenToUSD(token, balance);
                totalValue += tokenValueUSD;
            }
        }
        
        return totalValue;
    }

    function setTokenDecimals(address token, uint8 decimals) external onlyRole(ADMIN_ROLE) {
        if (!_supportedTokens[token]) revert TokenNotSupported();
        if (decimals == 0 || decimals > 77) revert InvalidDecimals();
        
        uint8 oldDecimals = _tokenDecimals[token];
        _tokenDecimals[token] = decimals;
        
        emit TokenDecimalsUpdated(token, oldDecimals, decimals);
    }

    function setTokenPriceFeed(address token, address priceFeedAddress) external onlyRole(ADMIN_ROLE) {
        if (!_supportedTokens[token]) revert TokenNotSupported();
        if (priceFeedAddress == address(0)) revert ZeroAddress();
        
        _tokenPriceFeeds[token] = AggregatorV3Interface(priceFeedAddress);
        
        emit TokenPriceFeedSet(token, priceFeedAddress);
    }

    function getTokenPriceFeed(address token) external view returns (address) {
        if (token == address(0)) {
            return address(ethUsdPriceFeed);
        }
        return address(_tokenPriceFeeds[token]);
    }
}