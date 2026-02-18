
const fs = require("fs");
const path = require("path");

async function main() {
  const depPath = path.join(__dirname, "..", "deployments.json");
  const deployments = JSON.parse(fs.readFileSync(depPath, "utf8"));

  const bridgeAddr = deployments.contracts.CrossChainTokenBridge;
  const tokenAddr = deployments.contracts.Token;

  const [owner] = await ethers.getSigners();
  const bridge = await ethers.getContractAt("CrossChainTokenBridge", bridgeAddr);
  const token = await ethers.getContractAt("TokenManager", tokenAddr);

  console.log("Bridge:", bridgeAddr);

  await (await bridge.pause()).wait();
  console.log("Paused");
  await (await bridge.unpause()).wait();
  console.log("Unpaused");

  // Sanity: threshold readable
  console.log("Threshold:", (await bridge.threshold()).toString());
  console.log("ValidatorCount:", (await bridge.validatorCount()).toString());
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

