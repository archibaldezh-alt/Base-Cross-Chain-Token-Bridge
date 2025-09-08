// base-crosschain-token-bridge/scripts/monitoring.js
const { ethers } = require("hardhat");
const fs = require("fs");

async function monitorBridgeOperations() {
  console.log("Monitoring Base Cross-Chain Token Bridge operations...");
  
  const bridgeAddress = "0x...";
  const bridge = await ethers.getContractAt("CrossChainBridgeV3", bridgeAddress);
  
  // Получение информации о мониторинге
  const monitoringData = {
    timestamp: new Date().toISOString(),
    bridgeAddress: bridgeAddress,
    transactionStats: {},
    chainStats: [],
    feeStats: {},
    performanceMetrics: {},
    alerts: []
  };
  
  // Статистика транзакций
  const transactionStats = await bridge.getTransactionStats();
  monitoringData.transactionStats = {
    totalTransactions: transactionStats.totalTransactions.toString(),
    successfulTransactions: transactionStats.successfulTransactions.toString(),
    failedTransactions: transactionStats.failedTransactions.toString(),
    successRate: transactionStats.successRate.toString()
  };
  
  // Статистика цепочек
  const chainCount = await bridge.getChainCount();
  for (let i = 0; i < chainCount; i++) {
    const chainInfo = await bridge.getChainInfo(i);
    monitoringData.chainStats.push({
      chainId: i,
      isActive: chainInfo.isActive,
      totalTransactions: chainInfo.totalTransactions.toString(),
      totalVolume: chainInfo.totalVolume.toString()
    });
  }
  
  // Статистика комиссий
  const feeStats = await bridge.getFeeStats();
  monitoringData.feeStats = {
    totalFeesCollected: feeStats.totalFeesCollected.toString(),
    avgFeeRate: feeStats.avgFeeRate.toString(),
    totalGasUsed: feeStats.totalGasUsed.toString()
  };
  
  // Показатели производительности
  const performanceMetrics = await bridge.getPerformanceMetrics();
  monitoringData.performanceMetrics = {
    avgProcessingTime: performanceMetrics.avgProcessingTime.toString(),
    maxProcessingTime: performanceMetrics.maxProcessingTime.toString(),
    minProcessingTime: performanceMetrics.minProcessingTime.toString()
  };
  
  // Проверка на проблемы
  if (parseInt(transactionStats.failedTransactions.toString()) > 10) {
    monitoringData.alerts.push("High number of failed transactions detected");
  }
  
  if (parseInt(feeStats.totalFeesCollected.toString()) < 1000) {
    monitoringData.alerts.push("Low fee collection detected");
  }
  
  // Сохранение отчета
  fs.writeFileSync(`./monitoring/bridge-monitor-${Date.now()}.json`, JSON.stringify(monitoringData, null, 2));
  
  console.log("Bridge monitoring completed successfully!");
  console.log("Alerts:", monitoringData.alerts.length);
}

monitorBridgeOperations()
  .catch(error => {
    console.error("Bridge monitoring error:", error);
    process.exit(1);
  });
