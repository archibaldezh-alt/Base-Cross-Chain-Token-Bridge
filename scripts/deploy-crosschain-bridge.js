const fs = require("fs");
const path = require("path");
require("dotenv").config();

function parseList(v) {
  return (v || "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deployer:", deployer.address);

  let token = process.env.BRIDGE_TOKEN || "";
  if (!token) {
    const Token = await ethers.getContractFactory("TokenManager");
    const t = await Token.deploy("BridgeToken", "BRG", 18);
    await t.deployed();
    token = t.address;
    console.log("Deployed BridgeToken (TokenManager):", token);
  }

  const thisChainId = Number(process.env.THIS_CHAIN_ID || "8453");
  const validators = parseList(process.env.VALIDATORS);
  const threshold = Number(process.env.THRESHOLD || "1");
  const finalValidators = validators.length ? validators : [deployer.address];

  const Bridge = await ethers.getContractFactory("CrossChainTokenBridge");
  const bridge = await Bridge.deploy(token, thisChainId, finalValidators, threshold);
  await bridge.deployed();

  console.log("CrossChainTokenBridge:", bridge.address);

  const out = {
    network: hre.network.name,
    chainId: (await ethers.provider.getNetwork()).chainId,
    deployer: deployer.address,
    contracts: {
      Token: token,
      CrossChainTokenBridge: bridge.address
    },
    params: { thisChainId, validators: finalValidators, threshold }
  };

  const outPath = path.join(__dirname, "..", "deployments.json");
  fs.writeFileSync(outPath, JSON.stringify(out, null, 2));
  console.log("Saved:", outPath);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
