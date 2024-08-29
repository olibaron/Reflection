const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("ReflectionToken", function () {
  let ReflectionToken;
  let token;
  let owner;
  let addr1;
  let addr2;
  let addr3;
  let addrs;
  let rewardsWallet;
  let liquidityWallet;
  let taxWallet;

  beforeEach(async function () {
    ReflectionToken = await ethers.getContractFactory("ReflectionToken");
    [owner, addr1, addr2, addr3, ...addrs] = await ethers.getSigners();

    // Use signers instead of random wallets for consistency in testing
    rewardsWallet = addr1.address;
    liquidityWallet = addr2.address;
    taxWallet = addr3.address;

    // Deploy the contract
    token = await ReflectionToken.deploy(
      "ReflectionToken",
      "RTK",
      rewardsWallet,
      liquidityWallet,
      taxWallet
    );

    // Wait for the deployment to be completed
    await token.waitForDeployment();

    // Use token.getAddress() to get the contract's address
    console.log("Token Contract Address:", await token.getAddress());

    await token.mint(owner.address, ethers.parseEther("1000")); // Mint some tokens to the owner
  });

  it("Should have correct initial settings", async function () {
    expect(await token.name()).to.equal("ReflectionToken");
    expect(await token.symbol()).to.equal("RTK");
    expect(await token.rewardsWallet()).to.equal(rewardsWallet);
    expect(await token.liquidityWallet()).to.equal(liquidityWallet);
    expect(await token.taxWallet()).to.equal(taxWallet);
  });

  it("Should correctly apply tax and liquidity fees on transfer", async function () {
    const initialOwnerBalance = await token.balanceOf(owner.address);
    const initialTaxWalletBalance = await token.balanceOf(taxWallet);
    const initialLiquidityBalance = await token.balanceOf(liquidityWallet);

    const amount = ethers.parseEther("100");
    const taxRate = BigInt(5); // 5%
    const liquidityRate = BigInt(2); // 2%

    const taxAmount = (amount * taxRate) / BigInt(100);
    const liquidityAmount = (amount * liquidityRate) / BigInt(100);
    const transferAmount = amount - taxAmount - liquidityAmount;

    // Transfer tokens from owner to addr1
    await token.transfer(addr1.address, amount);

    // Check the sender's balance after the transfer
    const ownerBalanceAfter = await token.balanceOf(owner.address);
    expect(ownerBalanceAfter).to.equal(initialOwnerBalance - amount);

    // Check the balance of addr1
    const addr1Balance = await token.balanceOf(addr1.address);
    expect(addr1Balance).to.equal(transferAmount);

    // Check the balance of the tax wallet
    const taxWalletBalanceAfter = await token.balanceOf(taxWallet);
    expect(taxWalletBalanceAfter).to.equal(initialTaxWalletBalance + taxAmount);

    // Check the balance of the liquidity wallet
    const liquidityBalanceAfter = await token.balanceOf(liquidityWallet);
    expect(liquidityBalanceAfter).to.equal(
      initialLiquidityBalance + liquidityAmount
    );
  });

  it("Should add recipient to holders list", async function () {
    await token.transfer(addr1.address, ethers.parseEther("100"));

    const holderExists = await token.holderExists(addr1.address);
    expect(holderExists).to.be.true;
  });

  it("Should exclude address from rewards", async function () {
    await token.setExcludedFromRewards(addr1.address, true);

    const isExcluded = await token.excludedFromRewards(addr1.address);
    expect(isExcluded).to.be.true;
  });

  it("Should set distribution interval correctly", async function () {
    await token.setDistributionInterval(14400); // 4 hours

    const interval = await token.distributionInterval();
    expect(interval).to.equal(14400);
  });

  it("Should distribute rewards correctly", async function () {
    // Transfer tokens to addr1 and addr2
    await token.transfer(addr1.address, ethers.parseEther("500"));
    await token.transfer(addr2.address, ethers.parseEther("500"));

    // Increase time to pass the distribution interval
    await ethers.provider.send("evm_increaseTime", [86400]); // fast-forward time by 1 day
    await ethers.provider.send("evm_mine"); // mine the next block

    // Send ETH to the contract as rewards
    const rewardsAmount = ethers.parseEther("10");
    await owner.sendTransaction({
      to: await token.getAddress(),
      value: rewardsAmount,
    });

    // Get balances before distribution
    const balanceAddr1Before = await ethers.provider.getBalance(addr1.address);
    const balanceAddr2Before = await ethers.provider.getBalance(addr2.address);

    // Distribute rewards
    const distributeTx = await token.distributeRewards();
    await distributeTx.wait(); // Ensure the transaction is mined

    // Get the balances of addr1 and addr2 after distribution
    const balanceAddr1After = await ethers.provider.getBalance(addr1.address);
    const balanceAddr2After = await ethers.provider.getBalance(addr2.address);

    // Calculate the expected rewards based on their token holdings
    const totalSupply = await token.totalSupply();
    const addr1TokenBalance = await token.balanceOf(addr1.address);
    const addr2TokenBalance = await token.balanceOf(addr2.address);

    const expectedRewardAddr1 =
      (BigInt(addr1TokenBalance) * BigInt(rewardsAmount) * BigInt(70)) /
      (BigInt(totalSupply) * BigInt(100));
    const expectedRewardAddr2 =
      (BigInt(addr2TokenBalance) * BigInt(rewardsAmount) * BigInt(70)) /
      (BigInt(totalSupply) * BigInt(100));

    // Check if addr1 and addr2 received the correct rewards
    expect(BigInt(balanceAddr1After)).to.equal(
      BigInt(balanceAddr1Before) + expectedRewardAddr1
    );
    expect(BigInt(balanceAddr2After)).to.equal(
      BigInt(balanceAddr2Before) + expectedRewardAddr2
    );
  });

  it("Should handle failed ETH transfers correctly", async function () {
    const MaliciousReceiver = await ethers.getContractFactory(
      "MaliciousReceiver"
    );
    const malicious = await MaliciousReceiver.deploy();
    await malicious.waitForDeployment(); // Ensure it's deployed before using it

    await token.transfer(malicious.target, ethers.parseEther("100"));

    await ethers.provider.send("evm_increaseTime", [86400]); // fast-forward time
    await ethers.provider.send("evm_mine"); // mine the next block

    const rewardsAmount = ethers.parseEther("10");
    await owner.sendTransaction({
      to: token.target,
      value: rewardsAmount,
    });

    await expect(token.distributeRewards()).to.be.revertedWith(
      "Transfer to holder failed."
    );
  });
});
