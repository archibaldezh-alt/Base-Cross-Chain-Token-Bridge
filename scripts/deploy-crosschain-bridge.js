
const { ethers } = require("hardhat");

async function main() {
  console.log("Deploying Base Cross-Chain Token Bridge...");
  
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);
  console.log("Account balance:", (await deployer.getBalance()).toString());

  // Деплой контракта
  const CrossChainBridge = await ethers.getContractFactory("CrossChainBridgeV3");
  const bridge = await CrossChainBridge.deploy(
    250, // 2.5% fee percentage
    ethers.utils.parseEther("0.001"), // 0.001 ETH minimum amount
    ethers.utils.parseEther("1000"), // 1000 ETH maximum amount
    3600 // 1 hour transaction timeout
  );

  await bridge.deployed();

  console.log("Base Cross-Chain Token Bridge deployed to:", bridge.address);
  
  // Сохраняем адрес для дальнейшего использования
  const fs = require("fs");
  const data = {
    bridge: bridge.address,
    owner: deployer.address
  };
  
  fs.writeFileSync("./config/deployment.json", JSON.stringify(data, null, 2));
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
