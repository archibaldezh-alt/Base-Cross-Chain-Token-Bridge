# base-crosschain-token-bridge/contracts/CrossChainTokenBridge.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract CrossChainTokenBridge is Ownable, ReentrancyGuard {
    struct BridgeTransaction {
        uint256 transactionId;
        address sender;
        address receiver;
        IERC20 token;
        uint256 amount;
        uint256 chainId;
        uint256 timestamp;
        bool completed;
        bytes32 txHash;
    }
    
    struct ChainConfig {
        bool enabled;
        address bridgeContract;
        uint256 chainId;
    }
    
    mapping(uint256 => BridgeTransaction) public transactions;
    mapping(uint256 => ChainConfig) public chainConfigs;
    mapping(bytes32 => bool) public processedTransactions;
    
    uint256 public nextTransactionId;
    uint256 public feePercentage;
    uint256 public minimumAmount;
    
    event TransactionInitiated(
        uint256 indexed transactionId,
        address indexed sender,
        address indexed receiver,
        address token,
        uint256 amount,
        uint256 chainId,
        uint256 timestamp
    );
    
    event TransactionCompleted(
        uint256 indexed transactionId,
        address indexed receiver,
        address token,
        uint256 amount
    );
    
    event ChainConfigured(
        uint256 indexed chainId,
        address bridgeContract,
        bool enabled
    );
    
    constructor(
        uint256 _feePercentage,
        uint256 _minimumAmount
    ) {
        feePercentage = _feePercentage;
        minimumAmount = _minimumAmount;
    }
    
    function configureChain(
        uint256 chainId,
        address bridgeContract,
        bool enabled
    ) external onlyOwner {
        chainConfigs[chainId] = ChainConfig({
            enabled: enabled,
            bridgeContract: bridgeContract,
            chainId: chainId
        });
        
        emit ChainConfigured(chainId, bridgeContract, enabled);
    }
    
    function initiateBridge(
        uint256 chainId,
        address receiver,
        IERC20 token,
        uint256 amount
    ) external payable nonReentrant {
        require(chainConfigs[chainId].enabled, "Chain not enabled");
        require(chainId != block.chainid, "Cannot bridge to same chain");
        require(amount >= minimumAmount, "Amount below minimum");
        require(token.balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        // Calculate fees
        uint256 fee = (amount * feePercentage) / 10000;
        uint256 amountToSend = amount - fee;
        
        // Transfer tokens to contract
        token.transferFrom(msg.sender, address(this), amount);
        
        // Deduct fee
        if (fee > 0) {
            token.transfer(owner(), fee);
        }
        
        // Create transaction record
        uint256 transactionId = nextTransactionId++;
        bytes32 txHash = keccak256(abi.encodePacked(
            msg.sender,
            receiver,
            address(token),
            amount,
            chainId,
            block.timestamp
        ));
        
        transactions[transactionId] = BridgeTransaction({
            transactionId: transactionId,
            sender: msg.sender,
            receiver: receiver,
            token: token,
            amount: amountToSend,
            chainId: chainId,
            timestamp: block.timestamp,
            completed: false,
            txHash: txHash
        });
        
        processedTransactions[txHash] = true;
        
        emit TransactionInitiated(
            transactionId,
            msg.sender,
            receiver,
            address(token),
            amount,
            chainId,
            block.timestamp
        );
    }
    
    function completeBridge(
        uint256 transactionId,
        bytes32 txHash
    ) external nonReentrant {
        BridgeTransaction storage transaction = transactions[transactionId];
        require(transaction.transactionId != 0, "Invalid transaction");
        require(!transaction.completed, "Transaction already completed");
        require(processedTransactions[txHash], "Transaction not initiated");
        
        // Verify transaction integrity
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
        
        emit TransactionCompleted(
            transactionId,
            transaction.receiver,
            address(transaction.token),
            transaction.amount
        );
    }
    
    function withdrawTokens(
        IERC20 token,
        uint256 amount
    ) external onlyOwner {
        token.transfer(owner(), amount);
    }
    
    function setFeePercentage(uint256 newFee) external onlyOwner {
        require(newFee <= 10000, "Fee too high"); // Maximum 100%
        feePercentage = newFee;
    }
    
    function setMinimumAmount(uint256 newMinimum) external onlyOwner {
        minimumAmount = newMinimum;
    }
    
    function getTransactionStatus(uint256 transactionId) external view returns (bool) {
        return transactions[transactionId].completed;
    }
}
