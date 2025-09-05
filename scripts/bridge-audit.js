// base-crosschain-token-bridge/scripts/audit.js
const { ethers } = require("hardhat");

async function auditBridge() {
  console.log("Auditing Base Cross-Chain Token Bridge...");
  
  const bridgeAddress = "0x...";
  const bridge = await ethers.getContractAt("CrossChainBridgeV3", bridgeAddress);
  
  // Получение информации о мосте
  const bridgeInfo = await bridge.getBridgeInfo();
  console.log("Bridge Info:", {
    totalTransactions: bridgeInfo.totalTransactions.toString(),
    completedTransactions: bridgeInfo.completedTransactions.toString(),
    pendingTransactions: bridgeInfo.pendingTransactions.toString(),
    totalVolume: bridgeInfo.totalVolume.toString(),
    totalFees: bridgeInfo.totalFees.toString(),
    activeChains: bridgeInfo.activeChains.toString()
  });
  
  // Получение информации о цепочках
  const chainInfo = await bridge.getChainInfo();
  console.log("Chain Info:", {
    totalChains: chainInfo.totalChains.toString(),
    activeChains: chainInfo.activeChains.toString(),
    totalGasUsed: chainInfo.totalGasUsed.toString()
  });
  
  // Получение информации о комиссиях
  const feeInfo = await bridge.getFeeInfo();
  console.log("Fee Info:", {
    totalFeesCollected: feeInfo.totalFeesCollected.toString(),
    avgFeeRate: feeInfo.avgFeeRate.toString(),
    minFee: feeInfo.minFee.toString(),
    maxFee: feeInfo.maxFee.toString()
  });
  
  // Получение статистики по транзакциям
  const transactionStats = await bridge.getTransactionStats();
  console.log("Transaction Stats:", {
    totalSuccessful: transactionStats.totalSuccessful.toString(),
    totalFailed: transactionStats.totalFailed.toString(),
    successRate: transactionStats.successRate.toString()
  });
  
  // Генерация аудит-отчета
  const fs = require("fs");
  const auditReport = {
    timestamp: new Date().toISOString(),
    bridgeAddress: bridgeAddress,
    audit: {
      bridgeInfo: bridgeInfo,
      chainInfo: chainInfo,
      feeInfo: feeInfo,
      transactionStats: transactionStats
    }
  };
  
  fs.writeFileSync("./reports/bridge-audit.json", JSON.stringify(auditReport, null, 2));
  
  console.log("Bridge audit completed successfully!");
}

auditBridge()
  .catch(error => {
    console.error("Audit error:", error);
    process.exit(1);
  });
