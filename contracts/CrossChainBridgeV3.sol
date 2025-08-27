// base-crosschain-token-bridge/contracts/CrossChainBridgeV3.sol
// Добавляем функционал токенов с различными характеристиками

struct TokenConfig {
    bool enabled;
    uint256 maxDailyVolume;
    uint256 maxTransactionAmount;
    uint256 minTransactionAmount;
    uint256 feeRate;
    uint256 maxFee;
    uint256 minFee;
    uint256 dailyVolume;
    uint256 lastResetTime;
}

struct TokenStatistics {
    uint256 totalTransferred;
    uint256 totalFeesCollected;
    uint256 transactionCount;
    uint256 averageTransactionValue;
    uint256 successRate;
}

mapping(address => TokenConfig) public tokenConfigs;
mapping(address => TokenStatistics) public tokenStats;
mapping(address => mapping(uint256 => uint256)) public dailyTransactions;

event TokenConfigUpdated(
    address indexed token,
    uint256 maxDailyVolume,
    uint256 maxTransactionAmount,
    uint256 feeRate
);

event TokenTransferred(
    address indexed token,
    address indexed from,
    address indexed to,
    uint256 amount,
    uint256 fee,
    uint256 timestamp
);

event TokenStatisticsUpdated(
    address indexed token,
    uint256 totalTransferred,
    uint256 totalFeesCollected,
    uint256 transactionCount
);

// Инициализация конфигурации токена
function initializeTokenConfig(
    address token,
    uint256 maxDailyVolume,
    uint256 maxTransactionAmount,
    uint256 minTransactionAmount,
    uint256 feeRate,
    uint256 maxFee,
    uint256 minFee
) external onlyOwner {
    require(token != address(0), "Invalid token address");
    
    tokenConfigs[token] = TokenConfig({
        enabled: true,
        maxDailyVolume: maxDailyVolume,
        maxTransactionAmount: maxTransactionAmount,
        minTransactionAmount: minTransactionAmount,
        feeRate: feeRate,
        maxFee: maxFee,
        minFee: minFee,
        dailyVolume: 0,
        lastResetTime: block.timestamp
    });
    
    emit TokenConfigUpdated(token, maxDailyVolume, maxTransactionAmount, feeRate);
}

// Обновление конфигурации токена
function updateTokenConfig(
    address token,
    uint256 maxDailyVolume,
    uint256 maxTransactionAmount,
    uint256 feeRate
) external onlyOwner {
    require(tokenConfigs[token].enabled, "Token not enabled");
    
    tokenConfigs[token].maxDailyVolume = maxDailyVolume;
    tokenConfigs[token].maxTransactionAmount = maxTransactionAmount;
    tokenConfigs[token].feeRate = feeRate;
    
    emit TokenConfigUpdated(token, maxDailyVolume, maxTransactionAmount, feeRate);
}

// Отключение токена
function disableToken(address token) external onlyOwner {
    require(tokenConfigs[token].enabled, "Token already disabled");
    tokenConfigs[token].enabled = false;
    emit TokenConfigUpdated(token, 0, 0, 0);
}

// Проверка ограничений токена
function validateTokenTransaction(
    address token,
    uint256 amount
) internal view returns (bool, string memory) {
    TokenConfig storage config = tokenConfigs[token];
    
    if (!config.enabled) {
        return (false, "Token not enabled");
    }
    
    // Проверка минимальной суммы
    if (amount < config.minTransactionAmount) {
        return (false, "Amount below minimum");
    }
    
    // Проверка максимальной суммы
    if (amount > config.maxTransactionAmount) {
        return (false, "Amount above maximum");
    }
    
    // Проверка дневного объема
    if (config.dailyVolume + amount > config.maxDailyVolume) {
        return (false, "Daily volume exceeded");
    }
    
    return (true, "");
}

// Расчет комиссии для токена
function calculateTokenFee(
    address token,
    uint256 amount
) internal view returns (uint256) {
    TokenConfig storage config = tokenConfigs[token];
    uint256 fee = (amount * config.feeRate) / 10000;
    
    // Применение мин/макс комиссий
    if (fee < config.minFee) {
        fee = config.minFee;
    } else if (fee > config.maxFee) {
        fee = config.maxFee;
    }
    
    return fee;
}

// Обновление статистики токена
function updateTokenStatistics(
    address token,
    uint256 amount,
    uint256 fee
) internal {
    TokenStatistics storage stats = tokenStats[token];
    stats.totalTransferred = stats.totalTransferred.add(amount);
    stats.totalFeesCollected = stats.totalFeesCollected.add(fee);
    stats.transactionCount = stats.transactionCount.add(1);
    
    // Обновление среднего значения транзакции
    if (stats.transactionCount > 0) {
        stats.averageTransactionValue = stats.totalTransferred.div(stats.transactionCount);
    }
    
    // Обновление дневного объема
    TokenConfig storage config = tokenConfigs[token];
    if (block.timestamp >= config.lastResetTime + 1 days) {
        config.dailyVolume = 0;
        config.lastResetTime = block.timestamp;
    }
    
    config.dailyVolume = config.dailyVolume.add(amount);
    
    emit TokenStatisticsUpdated(token, stats.totalTransferred, stats.totalFeesCollected, stats.transactionCount);
}

// Получение информации о конфигурации токена
function getTokenConfig(address token) external view returns (TokenConfig memory) {
    return tokenConfigs[token];
}

// Получение статистики токена
function getTokenStatistics(address token) external view returns (TokenStatistics memory) {
    return tokenStats[token];
}

// Получение доступного объема для токена
function getAvailableVolume(address token) external view returns (uint256) {
    TokenConfig storage config = tokenConfigs[token];
    if (block.timestamp >= config.lastResetTime + 1 days) {
        return config.maxDailyVolume;
    }
    return config.maxDailyVolume - config.dailyVolume;
}
