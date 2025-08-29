// base-crosschain-token-bridge/test/crosschain-token-bridge.test.js
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Base Cross-Chain Token Bridge", function () {
  let bridge;
  let token;
  let owner;
  let addr1;

  beforeEach(async function () {
    [owner, addr1] = await ethers.getSigners();
    
    // Деплой токена
    const TestToken = await ethers.getContractFactory("ERC20Token");
    token = await TestToken.deploy("Test Token", "TEST");
    await token.deployed();
    
    // Деплой Bridge контракта
    const CrossChainTokenBridge = await ethers.getContractFactory("CrossChainTokenBridgeV3");
    bridge = await CrossChainTokenBridge.deploy(
      250, // 2.5% fee percentage
      ethers.utils.parseEther("0.001"), // 0.001 ETH minimum amount
      ethers.utils.parseEther("1000"), // 1000 ETH maximum amount
      3600 // 1 hour transaction timeout
    );
    await bridge.deployed();
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await bridge.owner()).to.equal(owner.address);
    });

    it("Should initialize with correct parameters", async function () {
      expect(await bridge.feePercentage()).to.equal(250);
      expect(await bridge.minimumAmount()).to.equal(ethers.utils.parseEther("0.001"));
      expect(await bridge.maximumAmount()).to.equal(ethers.utils.parseEther("1000"));
    });
  });

  describe("Chain Configuration", function () {
    it("Should configure a chain", async function () {
      await expect(bridge.configureChain(
        1,
        addr1.address,
        true,
        100000,
        100
      )).to.emit(bridge, "ChainConfigured");
    });
  });

  describe("Bridge Operations", function () {
    beforeEach(async function () {
      await bridge.configureChain(
        1,
        addr1.address,
        true,
        100000,
        100
      );
    });

    it("Should initiate a bridge", async function () {
      await token.mint(owner.address, ethers.utils.parseEther("100"));
      await token.approve(bridge.address, ethers.utils.parseEther("100"));
      
      await expect(bridge.initiateBridge(
        1,
        addr1.address,
        token.address,
        ethers.utils.parseEther("10")
      )).to.emit(bridge, "TransactionInitiated");
    });
  });
});
