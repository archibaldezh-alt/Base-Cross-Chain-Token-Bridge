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
        require(newFee <= MAX_FEE_PERCENTAGE, "Fee too high"); // Maximum 100%
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
}
