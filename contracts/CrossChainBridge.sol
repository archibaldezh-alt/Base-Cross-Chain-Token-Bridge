// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract CrossChainBridgeV3 is Ownable, ReentrancyGuard {
    using MerkleProof for bytes32[];

    struct BridgeRequest {
        uint256 requestId;
        address sender;
        address receiver;
        IERC20 token;
        uint256 amount;
        uint256 chainId;
        uint256 timestamp;
        bool completed;
        bytes32 txHash;
        uint256 nonce;
        bytes signature;
        uint256 fee;
        uint256 sourceChainId;
        uint256 destinationChainId;
    }

    struct ChainConfig {
        bool enabled;
        address bridgeContract;
        uint256 chainId;
        uint256 gasLimit;
        uint256 fee;
        uint256 maxTransactionAmount;
        uint256 minTransactionAmount;
        uint256 dailyVolume;
        uint256 lastResetTime;
    }

    struct MerkleRoot {
        bytes32 root;
        uint256 timestamp;
        uint256 expiry;
        uint256 chainId;
    }

    struct BridgeStats {
        uint256 totalTransactions;
        uint256 completedTransactions;
        uint256 pendingTransactions;
        uint256 totalVolume;
        uint256 totalFees;
        uint256 activeChains;
        uint256 successRate;
        uint256 avgProcessingTime;
    }

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
        uint256 totalTransferred;
        uint256 totalFeesCollected;
        uint256 transactionCount;
        uint256 averageTransactionValue;
        uint256 successRate;
    }

    mapping(uint256 => BridgeRequest) public bridgeRequests;
    mapping(uint256 => ChainConfig) public chainConfigs;
    mapping(bytes32 => bool) public processedTransactions;
    mapping(bytes32 => MerkleRoot) public merkleRoots;
    mapping(address => TokenConfig) public tokenConfigs;
    
    uint256 public nextRequestId;
    uint256 public feePercentage;
    uint256 public minimumAmount;
    uint256 public maximumAmount;
    uint256 public transactionTimeout;
    uint256 public constant MAX_CHAIN_ID = 1000000;
    uint256 public constant MAX_FEE_PERCENTAGE = 10000; // 100%
    
    // Bridge statistics
    BridgeStats public bridgeStats;
    
    // Events
    event TransactionInitiated(
        uint256 indexed requestId,
        address indexed sender,
        address indexed receiver,
        address token,
        uint256 amount,
        uint256 chainId,
        uint256 timestamp,
        uint256 fee
    );
    
    event TransactionCompleted(
        uint256 indexed requestId,
        address indexed receiver,
        address token,
        uint256 amount,
        uint256 fee,
        uint256 timestamp
    );
    
    event ChainConfigured(
        uint256 indexed chainId,
        address bridgeContract,
        bool enabled,
        uint256 gasLimit,
        uint256 fee,
        uint256 maxTransactionAmount,
        uint256 minTransactionAmount
    );
    
    event FeeUpdated(uint256 newFee);
    event LimitUpdated(uint256 minimumAmount, uint256 maximumAmount);
    event TimeoutUpdated(uint256 newTimeout);
    event MerkleRootUpdated(bytes32 indexed root, uint256 timestamp, uint256 expiry, uint256 chainId);
    event TransactionCancelled(uint256 indexed requestId, address indexed sender);
    event TokenConfigUpdated(
        address indexed token,
        uint256 maxDailyVolume,
        uint256 maxTransactionAmount,
        uint256 feeRate,
        uint256 maxFee,
        uint256 minFee
    );
    event BridgeStatsUpdated(
        uint256 totalTransactions,
        uint256 completedTransactions,
        uint256 pendingTransactions,
        uint256 totalVolume,
        uint256 totalFees
    );

    constructor(
        uint256 _feePercentage,
        uint256 _minimumAmount,
        uint256 _maximumAmount,
        uint256 _transactionTimeout
    ) {
        require(_feePercentage <= MAX_FEE_PERCENTAGE, "Fee too high");
        feePercentage = _feePercentage;
        minimumAmount = _minimumAmount;
        maximumAmount = _maximumAmount;
        transactionTimeout = _transactionTimeout;
        
        // Initialize bridge stats
        bridgeStats = BridgeStats({
            totalTransactions: 0,
            completedTransactions: 0,
            pendingTransactions: 0,
            totalVolume: 0,
            totalFees: 0,
            activeChains: 0,
            successRate: 0,
            avgProcessingTime: 0
        });
    }

    // Configure chain
    function configureChain(
        uint256 chainId,
        address bridgeContract,
        bool enabled,
        uint256 gasLimit,
        uint256 fee,
        uint256 maxTransactionAmount,
        uint256 minTransactionAmount
    ) external onlyOwner {
        require(chainId > 0 && chainId < MAX_CHAIN_ID, "Invalid chain ID");
        require(bridgeContract != address(0), "Invalid bridge contract");
        require(gasLimit > 0, "Invalid gas limit");
        require(fee <= MAX_FEE_PERCENTAGE, "Fee too high"); // Maximum 100%
        require(maxTransactionAmount >= minTransactionAmount, "Invalid transaction limits");
        
        chainConfigs[chainId] = ChainConfig({
            enabled: enabled,
            bridgeContract: bridgeContract,
            chainId: chainId,
            gasLimit: gasLimit,
            fee: fee,
            maxTransactionAmount: maxTransactionAmount,
            minTransactionAmount: minTransactionAmount,
            dailyVolume: 0,
            lastResetTime: block.timestamp
        });
        
        if (enabled) {
            bridgeStats.activeChains++;
        }
        
        emit ChainConfigured(chainId, bridgeContract, enabled, gasLimit, fee, maxTransactionAmount, minTransactionAmount);
    }

    // Set fee percentage
    function setFeePercentage(uint256 newFee) external onlyOwner {
        require(newFee <= 10000, "Fee too high"); // 100%
        require(newFee >= 10, "Fee too low"); // Минимум 0.1%
    
        // Добавленная проверка
        require(newFee <= 10000, "Fee exceeds maximum");
        require(newFee >= 10, "Fee below minimum");
    
    feePercentage = newFee;
    emit FeeUpdated(newFee);
    }

    // Set amount limits
    function setAmountLimits(uint256 newMinimum, uint256 newMaximum) external onlyOwner {
        require(newMinimum <= newMaximum, "Minimum cannot exceed maximum");
        minimumAmount = newMinimum;
        maximumAmount = newMaximum;
        emit LimitUpdated(newMinimum, newMaximum);
    }

    // Set transaction timeout
    function setTransactionTimeout(uint256 newTimeout) external onlyOwner {
        transactionTimeout = newTimeout;
        emit TimeoutUpdated(newTimeout);
    }

    // Set token configuration
    function setTokenConfig(
        address token,
        uint256 maxDailyVolume,
        uint256 maxTransactionAmount,
        uint256 minTransactionAmount,
        uint256 feeRate,
        uint256 maxFee,
        uint256 minFee
    ) external onlyOwner {
        require(token != address(0), "Invalid token");
        require(maxTransactionAmount >= minTransactionAmount, "Invalid transaction limits");
        require(feeRate <= MAX_FEE_PERCENTAGE, "Fee rate too high");
        require(maxFee >= minFee, "Invalid fee limits");
        
        tokenConfigs[token] = TokenConfig({
            enabled: true,
            maxDailyVolume: maxDailyVolume,
            maxTransactionAmount: maxTransactionAmount,
            minTransactionAmount: minTransactionAmount,
            feeRate: feeRate,
            maxFee: maxFee,
            minFee: minFee,
            dailyVolume: 0,
            lastResetTime: block.timestamp,
            totalTransferred: 0,
            totalFeesCollected: 0,
            transactionCount: 0,
            averageTransactionValue: 0,
            successRate: 0
        });
        
        emit TokenConfigUpdated(token, maxDailyVolume, maxTransactionAmount, feeRate, maxFee, minFee);
    }

    // Initiate bridge
    function initiateBridge(
        uint256 chainId,
        address receiver,
        IERC20 token,
        uint256 amount,
        uint256 nonce,
        bytes calldata signature,
        uint256 sourceChainId,
        uint256 destinationChainId
    ) external payable nonReentrant {
        require(chainConfigs[chainId].enabled, "Chain not enabled");
        require(chainId != block.chainid, "Cannot bridge to same chain");
        require(amount >= minimumAmount, "Amount below minimum");
        require(amount <= maximumAmount, "Amount above maximum");
        require(token.balanceOf(msg.sender) >= amount, "Insufficient balance");
        require(chainConfigs[chainId].chainId == chainId, "Wrong chain ID");
        require(sourceChainId == block.chainid, "Invalid source chain");
        require(destinationChainId == chainId, "Invalid destination chain");
        
        // Validate token configuration
        TokenConfig storage tokenConfig = tokenConfigs[address(token)];
        if (tokenConfig.enabled) {
            require(amount >= tokenConfig.minTransactionAmount, "Token amount below minimum");
            require(amount <= tokenConfig.maxTransactionAmount, "Token amount above maximum");
            
            // Check daily volume
            if (block.timestamp >= tokenConfig.lastResetTime + 1 days) {
                tokenConfig.dailyVolume = 0;
                tokenConfig.lastResetTime = block.timestamp;
            }
            require(tokenConfig.dailyVolume + amount <= tokenConfig.maxDailyVolume, "Daily volume exceeded");
        }
        
        // Calculate fees
        uint256 fee = 0;
        if (tokenConfig.enabled) {
            fee = (amount * tokenConfig.feeRate) / 10000;
            if (fee < tokenConfig.minFee) {
                fee = tokenConfig.minFee;
            } else if (fee > tokenConfig.maxFee) {
                fee = tokenConfig.maxFee;
            }
        } else {
            fee = (amount * feePercentage) / 10000;
        }
        
        uint256 amountToSend = amount - fee;
        
        // Transfer tokens
        token.transferFrom(msg.sender, address(this), amount);
        
        // Deduct fees
        if (fee > 0) {
            token.transfer(owner(), fee);
        }
        
        // Create transaction
        uint256 transactionId = nextRequestId++;
        bytes32 txHash = keccak256(abi.encodePacked(
            msg.sender,
            receiver,
            address(token),
            amount,
            chainId,
            block.timestamp
        ));
        
        bridgeRequests[transactionId] = BridgeRequest({
            requestId: transactionId,
            sender: msg.sender,
            receiver: receiver,
            token: token,
            amount: amountToSend,
            chainId: chainId,
            timestamp: block.timestamp,
            completed: false,
            txHash: txHash,
            nonce: nonce,
            signature: signature,
            fee: fee,
            sourceChainId: sourceChainId,
            destinationChainId: destinationChainId
        });
        
        processedTransactions[txHash] = true;
        
        // Update bridge stats
        bridgeStats.totalTransactions = bridgeStats.totalTransactions.add(1);
        bridgeStats.pendingTransactions = bridgeStats.pendingTransactions.add(1);
        bridgeStats.totalVolume = bridgeStats.totalVolume.add(amount);
        
        emit TransactionInitiated(
            transactionId,
            msg.sender,
            receiver,
            address(token),
            amount,
            chainId,
            block.timestamp,
            fee
        );
    }

    // Complete bridge
    function completeBridge(
        uint256 transactionId,
        bytes32 txHash,
        uint256 chainId,
        bytes32[] calldata proof
    ) external nonReentrant {
        BridgeRequest storage transaction = bridgeRequests[transactionId];
        require(transaction.requestId != 0, "Invalid transaction");
        require(!transaction.completed, "Transaction already completed");
        require(processedTransactions[txHash], "Transaction not initiated");
        require(transaction.chainId == chainId, "Chain ID mismatch");
        require(block.timestamp < transaction.timestamp + transactionTimeout, "Transaction timeout");
        
        // Verify Merkle proof (if used)
        if (proof.length > 0) {
            // Verify Merkle proof
        }
        
        // Verify transaction hash
        bytes32 expectedHash = keccak256(abi.encodePacked(
            transaction.sender,
            transaction.receiver,
            address(transaction.token),
            transaction.amount,
            transaction.chainId,
            transaction.timestamp
        ));
        require(expectedHash == txHash, "Invalid transaction hash");
        
        // Transfer tokens to receiver
        transaction.token.transfer(transaction.receiver, transaction.amount);
        
        // Mark as completed
        transaction.completed = true;
        
        // Update bridge stats
        bridgeStats.completedTransactions = bridgeStats.completedTransactions.add(1);
        bridgeStats.pendingTransactions = bridgeStats.pendingTransactions.sub(1);
        bridgeStats.totalFees = bridgeStats.totalFees.add(transaction.fee);
        
        // Update token stats
        TokenConfig storage tokenConfig = tokenConfigs[address(transaction.token)];
        if (tokenConfig.enabled) {
            tokenConfig.dailyVolume = tokenConfig.dailyVolume.add(transaction.amount);
            tokenConfig.totalTransferred = tokenConfig.totalTransferred.add(transaction.amount);
            tokenConfig.totalFeesCollected = tokenConfig.totalFeesCollected.add(transaction.fee);
            tokenConfig.transactionCount = tokenConfig.transactionCount.add(1);
            tokenConfig.averageTransactionValue = tokenConfig.totalTransferred.div(tokenConfig.transactionCount);
            tokenConfig.successRate = (tokenConfig.transactionCount - 1).mul(10000).div(tokenConfig.transactionCount);
        }
        
        emit TransactionCompleted(
            transactionId,
            transaction.receiver,
            address(transaction.token),
            transaction.amount,
            transaction.fee,
            block.timestamp
        );
    }

    // Cancel transaction
    function cancelTransaction(
        uint256 transactionId
    ) external {
        BridgeRequest storage transaction = bridgeRequests[transactionId];
        require(transaction.requestId != 0, "Invalid transaction");
        require(!transaction.completed, "Transaction already completed");
        require(transaction.sender == msg.sender, "Not sender");
        require(block.timestamp >= transaction.timestamp + transactionTimeout, "Transaction not timed out");
        
        // Return tokens to sender
        transaction.token.transfer(transaction.sender, transaction.amount);
        
        // Mark as cancelled
        transaction.completed = true;
        
        // Update bridge stats
        bridgeStats.pendingTransactions = bridgeStats.pendingTransactions.sub(1);
        
        emit TransactionCancelled(transactionId, transaction.sender);
    }

    // Set Merkle root
    function setMerkleRoot(
        bytes32 root,
        uint256 expiry,
        uint256 chainId
    ) external onlyOwner {
        require(chainId > 0 && chainId < MAX_CHAIN_ID, "Invalid chain ID");
        
        merkleRoots[root] = MerkleRoot({
            root: root,
            timestamp: block.timestamp,
            expiry: expiry,
            chainId: chainId
        });
        
        emit MerkleRootUpdated(root, block.timestamp, expiry, chainId);
    }

    // Get transaction info
    function getTransactionInfo(uint256 transactionId) external view returns (BridgeRequest memory) {
        return bridgeRequests[transactionId];
    }

    // Get chain config
    function getChainConfig(uint256 chainId) external view returns (ChainConfig memory) {
        return chainConfigs[chainId];
    }

    // Check transaction status
    function getTransactionStatus(uint256 transactionId) external view returns (bool) {
        return bridgeRequests[transactionId].completed;
    }

    // Get bridge stats
    function getBridgeStats() external view returns (BridgeStats memory) {
        return bridgeStats;
    }

    // Get token config
    function getTokenConfig(address token) external view returns (TokenConfig memory) {
        return tokenConfigs[token];
    }

    // Get active chains
    function getActiveChains() external view returns (uint256[] memory) {
        uint256[] memory chains = new uint256[](100); // Example
        uint256 count = 0;
        for (uint256 i = 1; i < 100; i++) {
            if (chainConfigs[i].enabled) {
                chains[count++] = i;
            }
        }
        return chains;
    }

    // Get user transactions
    function getUserTransactions(address user) external view returns (uint256[] memory) {
        // Implementation would go here
        return new uint256[](0);
    }

    // Get available volume for token
    function getAvailableVolume(address token) external view returns (uint256) {
        TokenConfig storage config = tokenConfigs[token];
        if (config.enabled) {
            if (block.timestamp >= config.lastResetTime + 1 days) {
                return config.maxDailyVolume;
            }
            return config.maxDailyVolume - config.dailyVolume;
        }
        return 0;
    }

    // Get fee for transaction
    function calculateFee(
        address token,
        uint256 amount
    ) external view returns (uint256) {
        TokenConfig storage config = tokenConfigs[token];
        if (config.enabled) {
            uint256 fee = (amount * config.feeRate) / 10000;
            if (fee < config.minFee) {
                fee = config.minFee;
            } else if (fee > config.maxFee) {
                fee = config.maxFee;
            }
            return fee;
        }
        return (amount * feePercentage) / 10000;
    }

    // Update bridge stats
    function updateBridgeStats() external onlyOwner {
        // Calculate success rate
        if (bridgeStats.totalTransactions > 0) {
            bridgeStats.successRate = (bridgeStats.completedTransactions * 10000) / bridgeStats.totalTransactions;
        }
        
        emit BridgeStatsUpdated(
            bridgeStats.totalTransactions,
            bridgeStats.completedTransactions,
            bridgeStats.pendingTransactions,
            bridgeStats.totalVolume,
            bridgeStats.totalFees
        );
    }

    // Get transaction volume
    function getTransactionVolume() external view returns (uint256) {
        return bridgeStats.totalVolume;
    }

    // Get total fees
    function getTotalFees() external view returns (uint256) {
        return bridgeStats.totalFees;
    }

    // Get chain information
    function getChainInfo(uint256 chainId) external view returns (
        bool enabled,
        address bridgeContract,
        uint256 chainIdInfo,
        uint256 gasLimit,
        uint256 fee
    ) {
        ChainConfig storage config = chainConfigs[chainId];
        return (
            config.enabled,
            config.bridgeContract,
            config.chainId,
            config.gasLimit,
            config.fee
        );
    }

    // Check if transaction is valid
    function isValidTransaction(
        uint256 transactionId,
        bytes32 txHash,
        uint256 chainId
    ) external view returns (bool) {
        BridgeRequest storage transaction = bridgeRequests[transactionId];
        if (transaction.requestId == 0) return false;
        if (transaction.completed) return false;
        if (transaction.chainId != chainId) return false;
        if (transaction.txHash != txHash) return false;
        if (block.timestamp >= transaction.timestamp + transactionTimeout) return false;
        return true;
    }
    // Добавить функции:
function optimizeFees(
    uint256 chainId,
    uint256 amount
) external view returns (uint256) {
    // Оптимизация комиссий
    uint256 baseFee = (amount * 100) / 10000; // 1%
    uint256 optimizedFee = baseFee * (10000 - 500) / 10000; // Снижение на 5%
    return optimizedFee;
}

function getOptimizedRoute(
    uint256 chainId,
    uint256 amount
) external view returns (address, uint256) {
    // Получение оптимального маршрута
    return (address(0), 0); // Реализация в будущем
}

struct DynamicFee {
    uint256 chainId;
    uint256 baseFee;
    uint256 marketConditionFactor;
    uint256 networkCongestion;
    uint256 timeBasedAdjustment;
    uint256 lastUpdateTime;
    uint256 feeAdjustmentThreshold;
    bool enabled;
}

struct FeeHistory {
    uint256 chainId;
    uint256 oldFee;
    uint256 newFee;
    uint256 timestamp;
    string reason;
}

// Добавить маппинги:
mapping(uint256 => DynamicFee) public dynamicFees;
mapping(uint256 => FeeHistory[]) public feeHistory;

// Добавить события:
event DynamicFeeUpdated(
    uint256 indexed chainId,
    uint256 oldFee,
    uint256 newFee,
    uint256 timestamp,
    string reason
);

event FeeCalculationTriggered(
    uint256 indexed chainId,
    uint256 calculatedFee,
    uint256 timestamp
);

event FeeAdjustmentThresholdUpdated(
    uint256 indexed chainId,
    uint256 newThreshold,
    uint256 timestamp
);

// Добавить функции:
function setDynamicFee(
    uint256 chainId,
    uint256 baseFee,
    uint256 marketConditionFactor,
    uint256 networkCongestion,
    uint256 feeAdjustmentThreshold
) external onlyOwner {
    require(chainId > 0, "Invalid chain ID");
    require(baseFee <= 10000, "Base fee too high");
    require(marketConditionFactor <= 10000, "Market factor too high");
    require(networkCongestion <= 10000, "Network congestion too high");
    
    dynamicFees[chainId] = DynamicFee({
        chainId: chainId,
        baseFee: baseFee,
        marketConditionFactor: marketConditionFactor,
        networkCongestion: networkCongestion,
        timeBasedAdjustment: 0,
        lastUpdateTime: block.timestamp,
        feeAdjustmentThreshold: feeAdjustmentThreshold,
        enabled: true
    });
    
    emit DynamicFeeUpdated(chainId, 0, baseFee, block.timestamp, "Initial fee setup");
}

function updateDynamicFee(
    uint256 chainId,
    string memory reason
) external {
    require(dynamicFees[chainId].chainId == chainId, "Fee not configured");
    require(dynamicFees[chainId].enabled, "Fee not enabled");
    
    // Calculate new fee based on conditions
    uint256 newFee = calculateDynamicFee(chainId);
    
    // Check if adjustment is needed
    DynamicFee storage feeInfo = dynamicFees[chainId];
    uint256 feeDifference = newFee > feeInfo.baseFee ? 
        newFee - feeInfo.baseFee : 
        feeInfo.baseFee - newFee;
    
    if (feeDifference >= feeInfo.feeAdjustmentThreshold) {
        uint256 oldFee = feeInfo.baseFee;
        feeInfo.baseFee = newFee;
        feeInfo.lastUpdateTime = block.timestamp;
        
        // Record history
        FeeHistory memory history = FeeHistory({
            chainId: chainId,
            oldFee: oldFee,
            newFee: newFee,
            timestamp: block.timestamp,
            reason: reason
        });
        
        feeHistory[chainId].push(history);
        
        emit DynamicFeeUpdated(chainId, oldFee, newFee, block.timestamp, reason);
    }
}

function calculateDynamicFee(uint256 chainId) internal view returns (uint256) {
    DynamicFee storage feeInfo = dynamicFees[chainId];
    
    // Base fee calculation with market conditions
    uint256 baseFee = feeInfo.baseFee;
    
    // Market condition factor (simplified)
    uint256 marketFactor = feeInfo.marketConditionFactor;
    uint256 networkFactor = feeInfo.networkCongestion;
    
    // Time-based adjustment (simplified)
    uint256 timeFactor = 10000; // Base time factor
    
    // Calculate dynamic fee
    uint256 dynamicFee = baseFee + 
                        (marketFactor * 100) + 
                        (networkFactor * 50) + 
                        (timeFactor * 20);
    
    // Cap at maximum reasonable fee
    return dynamicFee > 10000 ? 10000 : dynamicFee; // 100%
}

function triggerFeeUpdate(uint256 chainId) external {
    DynamicFee storage feeInfo = dynamicFees[chainId];
    require(feeInfo.chainId == chainId, "Fee not configured");
    
    // Update fee based on current conditions
    uint256 newFee = calculateDynamicFee(chainId);
    
    // Update time-based adjustment
    feeInfo.timeBasedAdjustment = (block.timestamp % 3600) * 100; // Simplified
    
    emit FeeCalculationTriggered(chainId, newFee, block.timestamp);
}

function getDynamicFeeInfo(uint256 chainId) external view returns (DynamicFee memory) {
    return dynamicFees[chainId];
}

function getFeeHistory(uint256 chainId) external view returns (FeeHistory[] memory) {
    return feeHistory[chainId];
}

function getOptimalFee(uint256 chainId, uint256 amount) external view returns (uint256) {
    DynamicFee storage feeInfo = dynamicFees[chainId];
    
    // Calculate optimal fee based on transaction amount
    uint256 baseFee = feeInfo.baseFee;
    uint256 amountFactor = amount / 1000000000000000000; // Convert to ETH
    
    uint256 optimalFee = baseFee + (amountFactor * 10); // 0.01% per ETH
    
    return optimalFee > 10000 ? 10000 : optimalFee; // 100%
}

function setFeeAdjustmentThreshold(uint256 chainId, uint256 newThreshold) external onlyOwner {
    require(dynamicFees[chainId].chainId == chainId, "Fee not configured");
    
    dynamicFees[chainId].feeAdjustmentThreshold = newThreshold;
    
    emit FeeAdjustmentThresholdUpdated(chainId, newThreshold, block.timestamp);
}
    
    // Новые структуры для автоматического обновления комиссий
    struct DynamicFee {
        uint256 chainId;
        uint256 baseFee;
        uint256 marketConditionFactor;
        uint256 networkCongestion;
        uint256 timeBasedAdjustment;
        uint256 lastUpdateTime;
        uint256 feeAdjustmentThreshold;
        uint256 maxFee;
        uint256 minFee;
        bool enabled;
        uint256 feeAdjustmentWindow;
        uint256[] feeHistory;
        uint256[] marketDataHistory;
        uint256[] networkDataHistory;
        uint256[] adjustmentHistory;
        mapping(uint256 => bool) isFeeAdjustmentApplied;
    }
    
    struct FeeOptimizationConfig {
        address[] targetChains;
        uint256[] optimizationTargets;
        uint256[] optimizationThresholds;
        uint256[] optimizationWeights;
        uint256[] optimizationPeriods;
        uint256[] optimizationCapacities;
        uint256[] optimizationFrequencies;
        uint256[] optimizationMinFees;
        uint256[] optimizationMaxFees;
        bool[] optimizationEnabled;
        uint256[] optimizationLastUpdates;
        uint256[] optimizationCurrentFees;
        uint256[] optimizationAvgFees;
        uint256[] optimizationMinCapacities;
        uint256[] optimizationMaxCapacities;
        string[] optimizationMethods;
    }
    
    struct FeeMarketData {
        uint256 chainId;
        uint256 transactionVolume;
        uint256 gasPrice;
        uint256 networkActivity;
        uint256 priceImpact;
        uint256 liquidity;
        uint256 marketCap;
        uint256 tradingVolume;
        uint256 timestamp;
        uint256[] recentVolumes;
        uint256[] recentGasPrices;
        uint256[] recentActivities;
        uint256[] recentPrices;
        uint256[] recentLiquidity;
        uint256[] recentMarketCaps;
        uint256[] recentTradingVolumes;
    }
    
    struct FeeAdjustmentHistory {
        uint256 chainId;
        uint256 oldFee;
        uint256 newFee;
        uint256 timestamp;
        string reason;
        uint256 adjustmentType;
        uint256 adjustmentValue;
        uint256[] relatedMetrics;
        uint256[] relatedFactors;
        uint256[] adjustmentDetails;
    }
    
    // Новые маппинги
    mapping(uint256 => DynamicFee) public dynamicFees;
    mapping(address => FeeOptimizationConfig) public feeOptimizationConfigs;
    mapping(uint256 => FeeMarketData) public feeMarketData;
    mapping(uint256 => FeeAdjustmentHistory[]) public feeAdjustmentHistory;
    mapping(uint256 => uint256) public chainTransactionCount;
    mapping(uint256 => uint256) public chainVolume;
    mapping(uint256 => uint256) public chainLastUpdate;
    
    // Новые события
    event DynamicFeeUpdated(
        uint256 indexed chainId,
        uint256 oldFee,
        uint256 newFee,
        uint256 timestamp,
        string reason
    );
    
    event FeeOptimizationConfigUpdated(
        address indexed chain,
        uint256[] optimizationTargets,
        uint256[] optimizationThresholds,
        uint256[] optimizationWeights,
        uint256[] optimizationPeriods,
        bool[] optimizationEnabled
    );
    
    event FeeMarketDataUpdated(
        uint256 indexed chainId,
        uint256 transactionVolume,
        uint256 gasPrice,
        uint256 networkActivity,
        uint256 timestamp
    );
    
    event FeeAdjustmentTriggered(
        uint256 indexed chainId,
        uint256 calculatedFee,
        uint256 timestamp,
        string adjustmentType
    );
    
    event FeeOptimizationApplied(
        uint256 indexed chainId,
        uint256 optimizedFee,
        uint256 optimizationScore,
        uint256 timestamp
    );
    

    function setDynamicFee(
        uint256 chainId,
        uint256 baseFee,
        uint256 marketConditionFactor,
        uint256 networkCongestion,
        uint256 feeAdjustmentThreshold,
        uint256 maxFee,
        uint256 minFee,
        uint256 feeAdjustmentWindow
    ) external onlyOwner {
        require(chainId > 0, "Invalid chain ID");
        require(baseFee <= 10000, "Base fee too high");
        require(marketConditionFactor <= 10000, "Market factor too high");
        require(networkCongestion <= 10000, "Network congestion too high");
        require(feeAdjustmentThreshold <= 10000, "Adjustment threshold too high");
        require(maxFee >= minFee, "Invalid fee limits");
        
        dynamicFees[chainId] = DynamicFee({
            chainId: chainId,
            baseFee: baseFee,
            marketConditionFactor: marketConditionFactor,
            networkCongestion: networkCongestion,
            timeBasedAdjustment: 0,
            lastUpdateTime: block.timestamp,
            feeAdjustmentThreshold: feeAdjustmentThreshold,
            maxFee: maxFee,
            minFee: minFee,
            enabled: true,
            feeAdjustmentWindow: feeAdjustmentWindow,
            feeHistory: new uint256[](0),
            marketDataHistory: new uint256[](0),
            networkDataHistory: new uint256[](0),
            adjustmentHistory: new uint256[](0),
            isFeeAdjustmentApplied: new mapping(uint256 => bool)
        });
        
        emit DynamicFeeUpdated(chainId, 0, baseFee, block.timestamp, "Initial fee setup");
    }
    
    function updateFeeOptimizationConfig(
        address chain,
        uint256[] memory optimizationTargets,
        uint256[] memory optimizationThresholds,
        uint256[] memory optimizationWeights,
        uint256[] memory optimizationPeriods,
        bool[] memory optimizationEnabled
    ) external onlyOwner {
        require(optimizationTargets.length == optimizationThresholds.length, "Array length mismatch");
        require(optimizationTargets.length == optimizationWeights.length, "Array length mismatch");
        require(optimizationTargets.length == optimizationPeriods.length, "Array length mismatch");
        require(optimizationTargets.length == optimizationEnabled.length, "Array length mismatch");
        
        feeOptimizationConfigs[chain] = FeeOptimizationConfig({
            targetChains: new address[](0),
            optimizationTargets: optimizationTargets,
            optimizationThresholds: optimizationThresholds,
            optimizationWeights: optimizationWeights,
            optimizationPeriods: optimizationPeriods,
            optimizationCapacities: new uint256[](0),
            optimizationFrequencies: new uint256[](0),
            optimizationMinFees: new uint256[](0),
            optimizationMaxFees: new uint256[](0),
            optimizationEnabled: optimizationEnabled,
            optimizationLastUpdates: new uint256[](0),
            optimizationCurrentFees: new uint256[](0),
            optimizationAvgFees: new uint256[](0),
            optimizationMinCapacities: new uint256[](0),
            optimizationMaxCapacities: new uint256[](0),
            optimizationMethods: new string[](0)
        });
        
        emit FeeOptimizationConfigUpdated(
            chain,
            optimizationTargets,
            optimizationThresholds,
            optimizationWeights,
            optimizationPeriods,
            optimizationEnabled
        );
    }
    
    function updateMarketData(
        uint256 chainId,
        uint256 transactionVolume,
        uint256 gasPrice,
        uint256 networkActivity,
        uint256 priceImpact,
        uint256 liquidity,
        uint256 marketCap,
        uint256 tradingVolume
    ) external onlyOwner {
        require(chainId > 0, "Invalid chain ID");
        
        feeMarketData[chainId] = FeeMarketData({
            chainId: chainId,
            transactionVolume: transactionVolume,
            gasPrice: gasPrice,
            networkActivity: networkActivity,
            priceImpact: priceImpact,
            liquidity: liquidity,
            marketCap: marketCap,
            tradingVolume: tradingVolume,
            timestamp: block.timestamp,
            recentVolumes: new uint256[](10),
            recentGasPrices: new uint256[](10),
            recentActivities: new uint256[](10),
            recentPrices: new uint256[](10),
            recentLiquidity: new uint256[](10),
            recentMarketCaps: new uint256[](10),
            recentTradingVolumes: new uint256[](10)
        });
        
        // Обновить историю
        feeMarketData[chainId].recentVolumes[0] = transactionVolume;
        feeMarketData[chainId].recentGasPrices[0] = gasPrice;
        feeMarketData[chainId].recentActivities[0] = networkActivity;
        feeMarketData[chainId].recentPrices[0] = priceImpact;
        feeMarketData[chainId].recentLiquidity[0] = liquidity;
        feeMarketData[chainId].recentMarketCaps[0] = marketCap;
        feeMarketData[chainId].recentTradingVolumes[0] = tradingVolume;
        
        emit FeeMarketDataUpdated(
            chainId,
            transactionVolume,
            gasPrice,
            networkActivity,
            block.timestamp
        );
    }
    
    function calculateDynamicFee(
        uint256 chainId,
        uint256 amount
    ) external view returns (uint256) {
        DynamicFee storage feeInfo = dynamicFees[chainId];
        FeeMarketData storage market = feeMarketData[chainId];
        
        if (!feeInfo.enabled) {
            return feeInfo.baseFee;
        }
        
        // Базовая формула динамического расчета комиссии
        uint256 baseFee = feeInfo.baseFee;
        
        // Множитель рыночных условий
        uint256 marketFactor = market.transactionVolume > 0 ? 
            (market.transactionVolume * feeInfo.marketConditionFactor) / 1000000000 : 0;
            
        // Множитель сетевой загрузки
        uint256 networkFactor = market.networkActivity > 0 ? 
            (market.networkActivity * feeInfo.networkCongestion) / 1000000 : 0;
            
        // Временной фактор
        uint256 timeFactor = (block.timestamp % 3600) * 1000; // 1000 wei за час
        
        // Общий коэффициент
        uint256 totalMultiplier = baseFee + 
                                marketFactor + 
                                networkFactor + 
                                timeFactor;
        
        // Ограничение максимальной и минимальной комиссии
        uint256 calculatedFee = totalMultiplier;
        if (calculatedFee > feeInfo.maxFee) {
            calculatedFee = feeInfo.maxFee;
        }
        if (calculatedFee < feeInfo.minFee) {
            calculatedFee = feeInfo.minFee;
        }
        
        // Применить множитель объема
        if (amount > 0) {
            uint256 volumeFactor = amount / 1000000000000000000; // 1 ETH
            calculatedFee = calculatedFee + (volumeFactor * 100000000000000000); // 0.1 ETH за каждый ETH
        }
        
        return calculatedFee > 10000 ? 10000 : calculatedFee; // Максимум 100%
    }
    
    function triggerFeeUpdate(
        uint256 chainId,
        uint256 amount
    ) external {
        DynamicFee storage feeInfo = dynamicFees[chainId];
        require(feeInfo.enabled, "Fee not enabled");
        
        // Проверка времени обновления
        require(block.timestamp >= feeInfo.lastUpdateTime + feeInfo.feeAdjustmentWindow, "Too early for fee update");
        
        // Расчет новой комиссии
        uint256 newFee = calculateDynamicFee(chainId, amount);
        
        // Проверка изменения комиссии
        uint256 feeDifference = newFee > feeInfo.baseFee ? 
            newFee - feeInfo.baseFee : 
            feeInfo.baseFee - newFee;
        
        if (feeDifference >= feeInfo.feeAdjustmentThreshold) {
            // Обновить комиссию
            uint256 oldFee = feeInfo.baseFee;
            feeInfo.baseFee = newFee;
            feeInfo.lastUpdateTime = block.timestamp;
            
            // Добавить в историю
            feeInfo.feeHistory.push(newFee);
            feeInfo.adjustmentHistory.push(feeDifference);
            

            feeAdjustmentHistory[chainId].push(FeeAdjustmentHistory({
                chainId: chainId,
                oldFee: oldFee,
                newFee: newFee,
                timestamp: block.timestamp,
                reason: "Automatic adjustment",
                adjustmentType: 1, // 1 - автоматическое
                adjustmentValue: feeDifference,
                relatedMetrics: new uint256[](0),
                relatedFactors: new uint256[](0),
                adjustmentDetails: new uint256[](0)
            }));
            
            emit DynamicFeeUpdated(chainId, oldFee, newFee, block.timestamp, "Automatic adjustment");
        }
        
        emit FeeAdjustmentTriggered(chainId, newFee, block.timestamp, "Automatic");
    }
    
    function applyFeeOptimization(
        uint256 chainId,
        uint256 amount
    ) external {
        FeeMarketData storage market = feeMarketData[chainId];
        DynamicFee storage feeInfo = dynamicFees[chainId];
        
        require(feeInfo.enabled, "Fee not enabled");
        
        // Простая логика оптимизации
        uint256 baseFee = feeInfo.baseFee;
        uint256 optimizationScore = 0;
        
        // Оптимизация на основе объема
        if (market.transactionVolume > 1000000000000000000000) { // 1000 ETH
            optimizationScore += 2000; // 20%
        }
        
        // Оптимизация на основе сетевой активности
        if (market.networkActivity > 5000) { // Высокая активность
            optimizationScore += 1500; // 15%
        }
        
        // Оптимизация на основе ликвидности
        if (market.liquidity > 10000000000000000000000) { // 10000 ETH
            optimizationScore += 1000; // 10%
        }
        
        // Расчет оптимизированной комиссии
        uint256 optimizedFee = baseFee - (baseFee * optimizationScore) / 10000;
        
        // Применить ограничения
        if (optimizedFee < feeInfo.minFee) {
            optimizedFee = feeInfo.minFee;
        }
        if (optimizedFee > feeInfo.maxFee) {
            optimizedFee = feeInfo.maxFee;
        }
        
        // Обновить комиссию
        uint256 oldFee = feeInfo.baseFee;
        feeInfo.baseFee = optimizedFee;
        feeInfo.lastUpdateTime = block.timestamp;
        
        // Добавить в историю
        feeInfo.feeHistory.push(optimizedFee);
        
        emit FeeOptimizationApplied(chainId, optimizedFee, optimizationScore, block.timestamp);
    }
    
    function getDynamicFeeInfo(uint256 chainId) external view returns (DynamicFee memory) {
        return dynamicFees[chainId];
    }
    
    function getFeeMarketData(uint256 chainId) external view returns (FeeMarketData memory) {
        return feeMarketData[chainId];
    }
    
    function getFeeAdjustmentHistory(uint256 chainId) external view returns (FeeAdjustmentHistory[] memory) {
        return feeAdjustmentHistory[chainId];
    }
    
    function getOptimizationConfig(address chain) external view returns (FeeOptimizationConfig memory) {
        return feeOptimizationConfigs[chain];
    }
    
    function getChainStats(uint256 chainId) external view returns (
        uint256 transactionCount,
        uint256 volume,
        uint256 avgFee,
        uint256 lastUpdate,
        uint256 currentFee
    ) {
        return (
            chainTransactionCount[chainId],
            chainVolume[chainId],
            dynamicFees[chainId].baseFee,
            chainLastUpdate[chainId],
            dynamicFees[chainId].baseFee
        );
    }
    
    function getFeeOptimizationScore(
        uint256 chainId,
        uint256 amount
    ) external view returns (uint256) {
        FeeMarketData storage market = feeMarketData[chainId];
        DynamicFee storage feeInfo = dynamicFees[chainId];
        
        uint256 score = 0;
        
        // Оценка на основе объема
        if (market.transactionVolume > 1000000000000000000000) { // 1000 ETH
            score += 2000;
        }
        
        // Оценка на основе активности
        if (market.networkActivity > 5000) {
            score += 1500;
        }
        
        // Оценка на основе ликвидности
        if (market.liquidity > 10000000000000000000000) { // 10000 ETH
            score += 1000;
        }
        
        // Оценка на основе объема транзакций
        if (amount > 1000000000000000000) { // 1 ETH
            score += 500;
        }
        
        return score > 10000 ? 10000 : score;
    }
    
    function getOptimizedFee(
        uint256 chainId,
        uint256 amount
    ) external view returns (uint256) {
        return calculateDynamicFee(chainId, amount);
    }
    
    function getFeeHistory(uint256 chainId, uint256 limit) external view returns (uint256[] memory) {
        DynamicFee storage feeInfo = dynamicFees[chainId];
        uint256[] memory history = new uint256[](limit < feeInfo.feeHistory.length ? limit : feeInfo.feeHistory.length);
        
        for (uint256 i = 0; i < history.length; i++) {
            history[i] = feeInfo.feeHistory[feeInfo.feeHistory.length - 1 - i];
        }
        
        return history;
    }
    
    function getFeeStats() external view returns (
        uint256 totalChains,
        uint256 activeChains,
        uint256 avgFee,
        uint256 totalFeeUpdates,
        uint256[] memory chainIds
    ) {
        uint256 totalChainsCount = 0;
        uint256 activeChainsCount = 0;
        uint256 totalFeeSum = 0;
        uint256 totalFeeUpdatesCount = 0;
        
        // Подсчет статистики
        for (uint256 i = 1; i < 1000; i++) {
            if (dynamicFees[i].chainId != 0) {
                totalChainsCount++;
                totalFeeSum = totalFeeSum.add(dynamicFees[i].baseFee);
                totalFeeUpdatesCount = totalFeeUpdatesCount.add(dynamicFees[i].feeHistory.length);
                
                if (dynamicFees[i].enabled) {
                    activeChainsCount++;
                }
            }
        }
        
        uint256 avgFeeValue = totalChainsCount > 0 ? totalFeeSum / totalChainsCount : 0;
        
        return (
            totalChainsCount,
            activeChainsCount,
            avgFeeValue,
            totalFeeUpdatesCount,
            new uint256[](0) // Возвращаем пустой массив для примера
        );
    }
    
    function updateChainStats(
        uint256 chainId,
        uint256 transactionCount,
        uint256 volume
    ) external {
        require(chainId > 0, "Invalid chain ID");
        chainTransactionCount[chainId] = chainTransactionCount[chainId].add(transactionCount);
        chainVolume[chainId] = chainVolume[chainId].add(volume);
        chainLastUpdate[chainId] = block.timestamp;
    }
    
    function resetFeeHistory(uint256 chainId) external onlyOwner {
        require(chainId > 0, "Invalid chain ID");
        DynamicFee storage feeInfo = dynamicFees[chainId];
        feeInfo.feeHistory = new uint256[](0);
        feeInfo.adjustmentHistory = new uint256[](0);
    }
}
