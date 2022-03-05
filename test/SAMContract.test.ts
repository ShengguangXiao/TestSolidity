const { assert, expect } = require("chai");
const hre = require("hardhat");
const { web3 } = require("hardhat");
const LFGTokenArt = hre.artifacts.require("LFGToken");
const LFGNFTArt = hre.artifacts.require("LFGNFT");
const SAMContractArt = hre.artifacts.require("SAMContract");
const BN = require("bn.js");
const { createImportSpecifier } = require("typescript");

describe("SAMContract", function () {
  let LFGToken = null;
  let LFGNFT = null;
  let SAMContract = null;
  let accounts = ["", "", "", "", "", "", ""],
    minter, burnAddress, revenueAddress;

  before("Deploy contract", async function () {
    try {
      [accounts[0], accounts[1], accounts[2], accounts[3], accounts[4], accounts[5], accounts[6], minter, burnAddress, revenueAddress]
        = await web3.eth.getAccounts();
      LFGToken = await LFGTokenArt.new("LFG Token",
        "LFG",
        "1000000000000000000000000000", minter);

      LFGNFT = await LFGNFTArt.new();

      SAMContract = await SAMContractArt.new(minter, LFGToken.address, burnAddress, revenueAddress);

      // This one must call from owner
      await SAMContract.setNftContractWhitelist(LFGNFT.address, true, { from: minter });

      // 10% royalties fee
      await SAMContract.updateroyaltiesFeeRate(1000, { from: minter });

    } catch (err) {
      console.log(err);
    }
  });

  it("test buy now feature", async function () {
    let supply = await LFGNFT.totalSupply();
    console.log("supply ", supply.toString());

    await LFGNFT.mint(2, accounts[2], { from: minter });

    supply = await LFGNFT.totalSupply();
    console.log("supply ", supply.toString());
    let account2TokenIds = await LFGNFT.tokensOfOwner(accounts[2]);
    console.log("tokenIds of account2 ", JSON.stringify(account2TokenIds));

    await LFGNFT.approve(SAMContract.address, 1, { from: accounts[2] });

    const latestBlock = await hre.ethers.provider.getBlock("latest");
    console.log("latestBlock ", latestBlock);

    await SAMContract.addListing(LFGNFT.address, account2TokenIds[0], "10000000", "20000000", latestBlock["timestamp"] + 1, 3600 * 24,
      false, 0, 0, { from: accounts[2] });

    let listingResult = await SAMContract.listingOfAddr(accounts[2]);
    console.log("getListingResult ", JSON.stringify(listingResult));
    assert.equal(listingResult.length, 1);
    let listingId = listingResult[0][0];

    const testDepositAmount = "100000000000000000000000";
    await LFGToken.transfer(accounts[1], testDepositAmount);

    let balance = await LFGToken.balanceOf(accounts[1]);
    console.log("account 1 balance ", balance.toString());

    await LFGToken.approve(SAMContract.address, testDepositAmount, { from: accounts[1] });

    await SAMContract.buyNow(listingId, { from: accounts[1] });

    let account1TokenIds = await LFGNFT.tokensOfOwner(accounts[1]);
    console.log("tokenIds of account 1 ", JSON.stringify(account1TokenIds));
    assert.equal(account1TokenIds[0], "1");

    account2TokenIds = await LFGNFT.tokensOfOwner(accounts[2]);
    console.log("tokenIds of account0 ", JSON.stringify(account2TokenIds));
    assert.equal(account2TokenIds[0], "2");

    let balanceOfAccount2 = await LFGToken.balanceOf(accounts[2]);
    console.log("Balance of account 2 ", balanceOfAccount2.toString());

    const account1Tokens = await SAMContract.addrTokens(accounts[1]);
    console.log("Escrow tokens of account 1 ", JSON.stringify(account1Tokens));

    // await SAMContract.claimToken({ from: accounts[2] });

    // account2Tokens = await SAMContract.addrTokens(accounts[2]);
    // console.log("After claim, Escrow tokens of account 2 ", JSON.stringify(account2Tokens));
    balanceOfAccount2 = await LFGToken.balanceOf(accounts[2]);
    console.log("Balance of account 2 ", balanceOfAccount2.toString());
    assert.equal(balanceOfAccount2.toString(), "20000000");

    listingResult = await SAMContract.listingOfAddr(accounts[2]);
    assert.equal(listingResult.length, 0);

    let burnAmount = await LFGToken.balanceOf(burnAddress);
    console.log("Burn amount ", burnAmount.toString());
    assert.equal(burnAmount.toString(), "250000");
  });

  it("test auction and bidding", async function () {
    let supply = await LFGNFT.totalSupply();
    console.log("supply ", supply.toString());

    //await LFGNFT.mint(2, accounts[2], {from: minter});

    supply = await LFGNFT.totalSupply();
    console.log("supply ", supply.toString());
    let account2TokenIds = await LFGNFT.tokensOfOwner(accounts[2]);
    console.log("tokenIds of account2 ", JSON.stringify(account2TokenIds));

    await LFGNFT.approve(SAMContract.address, account2TokenIds[0], { from: accounts[2] });

    const latestBlock = await hre.ethers.provider.getBlock("latest");
    await SAMContract.addListing(LFGNFT.address, account2TokenIds[0], "10000000", "20000000", latestBlock["timestamp"] + 1, 3600 * 24,
      false, 0, 0, { from: accounts[2] });

    let listingResult = await SAMContract.listingOfAddr(accounts[2]);
    console.log("getListingResult ", JSON.stringify(listingResult));
    assert.equal(listingResult.length, 1);

    let listingId = listingResult[0][0];

    const testDepositAmount = "100000000000000000000000";
    for (let accountId = 3; accountId < 6; ++accountId) {
      await LFGToken.transfer(accounts[accountId], testDepositAmount);
      await LFGToken.approve(SAMContract.address, testDepositAmount, { from: accounts[accountId] }); // to charge fees
    }

    await expect(
      SAMContract.placeBid(listingId, "10000000", { from: accounts[3] })
    ).to.be.revertedWith("Bid price too low");

    await SAMContract.placeBid(listingId, "11000000", { from: accounts[3] });

    await expect(
      SAMContract.placeBid(listingId, "11000000", { from: accounts[4] })
    ).to.be.revertedWith("Bid price too low");

    await SAMContract.placeBid(listingId, "12000000", { from: accounts[4] });
    await SAMContract.placeBid(listingId, "15000000", { from: accounts[5] });

    const biddings = await SAMContract.biddingOfListing(listingId);
    console.log("All biddings: ", JSON.stringify(biddings));

    await expect(
      SAMContract.claimNft(biddings[0][0], { from: accounts[3] })
    ).to.be.revertedWith("The bidding period haven't complete");

    const today = Math.round(new Date() / 1000);
    await hre.network.provider.send("evm_setNextBlockTimestamp", [today + 3601 * 24]);
    await hre.network.provider.send("evm_mine");

    await expect(
      SAMContract.claimNft(biddings[0][0], { from: accounts[3] })
    ).to.be.revertedWith("The bidding is not the highest price");

    await SAMContract.claimNft(biddings[2][0], { from: accounts[5] });
    listingResult = await SAMContract.listingOfAddr(accounts[2]);
    assert.equal(listingResult.length, 0);

    let balanceOfAccount2 = await LFGToken.balanceOf(accounts[2]);
    console.log("Balance of account 2 ", balanceOfAccount2.toString());
    assert.equal(balanceOfAccount2.toString(), "35000000");

    // Account 3 bid failed, should be auto refunded
    let balanceOfAccount3 = await LFGToken.balanceOf(accounts[3]);
    console.log("Balance of account 3 ", balanceOfAccount3.toString());
    assert.equal(balanceOfAccount3.toString(), testDepositAmount);

    let burnAmount = await LFGToken.balanceOf(burnAddress);
    console.log("Burn amount ", burnAmount.toString());
    assert.equal(burnAmount.toString(), "437500");

    let revenueAmount = await SAMContract.revenueAmount();
    assert.equal(revenueAmount.toString(), "437500");

    let revenueBalance = await LFGToken.balanceOf(revenueAddress);
    console.log("Revenue account balance ", revenueBalance.toString());
    assert.equal(revenueBalance.toString(), "437500");
  });

  it("test remove listing ", async function () {
    let supply = await LFGNFT.totalSupply();
    console.log("supply ", supply.toString());

    await LFGNFT.mint(2, accounts[2], { from: minter });

    supply = await LFGNFT.totalSupply();
    console.log("supply ", supply.toString());
    let account2TokenIds = await LFGNFT.tokensOfOwner(accounts[2]);
    console.log("tokenIds of account2 ", JSON.stringify(account2TokenIds));

    await LFGNFT.approve(SAMContract.address, account2TokenIds[0], { from: accounts[2] });

    const latestBlock = await hre.ethers.provider.getBlock("latest");
    await SAMContract.addListing(LFGNFT.address, account2TokenIds[0], "10000000", "20000000", latestBlock["timestamp"] + 1, 3600 * 24,
      false, 0, 0, { from: accounts[2] });

    let listingResult = await SAMContract.listingOfAddr(accounts[2]);
    console.log("getListingResult ", JSON.stringify(listingResult));
    assert.equal(listingResult.length, 1);
    let listingId = listingResult[0][0];

    await expect(
      SAMContract.removeListing(listingId, { from: accounts[2] })
    ).to.be.revertedWith("The listing haven't expired");

    const today = Math.round(new Date() / 1000);
    await hre.network.provider.send("evm_setNextBlockTimestamp", [today + 3601 * 48]);
    await hre.network.provider.send("evm_mine");

    await expect(
      SAMContract.removeListing(listingId, { from: accounts[1] })
    ).to.be.revertedWith("Only seller can remove the listing");

    await SAMContract.removeListing(listingId, { from: accounts[2] });
    listingResult = await SAMContract.listingOfAddr(accounts[2]);
    console.log("getListingResult ", JSON.stringify(listingResult));
    assert.equal(listingResult.length, 0);
  });

  it("test dutch auction ", async function () {
    let account2TokenIds = await LFGNFT.tokensOfOwner(accounts[2]);
    console.log("tokenIds of account2 ", JSON.stringify(account2TokenIds));

    await LFGNFT.approve(SAMContract.address, account2TokenIds[0], { from: accounts[2] });

    let latestBlock = await hre.ethers.provider.getBlock("latest");
    await SAMContract.addListing(LFGNFT.address, account2TokenIds[0], "10000000", "20000000", latestBlock["timestamp"] + 1, 3600 * 24,
      true, 3600, 100000, { from: accounts[2] });

    let listingResult = await SAMContract.listingOfAddr(accounts[2]);
    console.log("getListingResult ", JSON.stringify(listingResult));
    assert.equal(listingResult.length, 1);
    let listingId = listingResult[0][0];

    await expect(
      SAMContract.removeListing(listingId, { from: accounts[2] })
    ).to.be.revertedWith("The listing haven't expired");

    latestBlock = await hre.ethers.provider.getBlock("latest");
    await hre.network.provider.send("evm_setNextBlockTimestamp", [latestBlock["timestamp"] + 3600 * 12]);
    await hre.network.provider.send("evm_mine");

    let currentPrice = await SAMContract.getPrice(listingId);
    console.log("currentPrice ", currentPrice.toString());

    await SAMContract.buyNow(listingId, { from: accounts[1] });

    let account1TokenIds = await LFGNFT.tokensOfOwner(accounts[1]);
    console.log("tokenIds of account 1 ", JSON.stringify(account1TokenIds));
    assert.equal(account1TokenIds[1], "4");

    let balanceOfAccount2 = await LFGToken.balanceOf(accounts[2]);
    console.log("Balance of account 2 ", balanceOfAccount2.toString());

    const account1Tokens = await SAMContract.addrTokens(accounts[1]);
    console.log("Escrow tokens of account 1 ", JSON.stringify(account1Tokens));

    balanceOfAccount2 = await LFGToken.balanceOf(accounts[2]);
    console.log("Balance of account 2 ", balanceOfAccount2.toString());
    assert.equal(balanceOfAccount2.toString(), "43800000");

    listingResult = await SAMContract.listingOfAddr(accounts[2]);
    assert.equal(listingResult.length, 0);

    // The price is 8800000, charge 2.5% fee, and burn 50% of the fee, so burn 110000, revenue 110000
    let burnAccBal = await LFGToken.balanceOf(burnAddress);
    console.log("burnAccBal ", burnAccBal.toString());
    assert.equal(burnAccBal.toString(), "547500");

    let totalBurnAmount = await SAMContract.totalBurnAmount();
    console.log("totalBurnAmount ", burnAccBal.toString());
    assert.equal(totalBurnAmount.toString(), "547500");

    // Increased renuve 8800000 * 2.5% * 50% = 110000
    let revenueAmount = await SAMContract.revenueAmount();
    assert.equal(revenueAmount.toString(), "547500");

    let revenueBalance = await LFGToken.balanceOf(revenueAddress);
    console.log("Revenue account balance ", revenueBalance.toString());
    assert.equal(revenueBalance.toString(), "547500");
  });

  it("test royalties payment after sell", async function () {
    let supply = await LFGNFT.totalSupply();
    console.log("supply ", supply.toString());

    await LFGNFT.mint(1, accounts[2], { from: minter });

    supply = await LFGNFT.totalSupply();
    console.log("supply ", supply.toString());
    let account2TokenIds = await LFGNFT.tokensOfOwner(accounts[2]);
    console.log("tokenIds of account2 ", JSON.stringify(account2TokenIds));

    const lastIndex = account2TokenIds.length - 1;

    await LFGNFT.setRoyalty(account2TokenIds[lastIndex], accounts[6], 2000, { from: minter });

    await LFGNFT.approve(SAMContract.address, account2TokenIds[lastIndex], { from: accounts[2] });

    const latestBlock = await hre.ethers.provider.getBlock("latest");
    console.log("latestBlock ", latestBlock);

    await SAMContract.addListing(LFGNFT.address, account2TokenIds[lastIndex], "10000000", "20000000", latestBlock["timestamp"] + 1, 3600 * 24,
      false, 0, 0, { from: accounts[2] });

    let listingResult = await SAMContract.listingOfAddr(accounts[2]);
    console.log("getListingResult ", JSON.stringify(listingResult));
    assert.equal(listingResult.length, 1);
    let listingId = listingResult[0][0];

    const testDepositAmount = "100000000000000000000000";
    await LFGToken.transfer(accounts[1], testDepositAmount);

    let balance = await LFGToken.balanceOf(accounts[1]);
    console.log("account 1 balance ", balance.toString());

    await LFGToken.approve(SAMContract.address, testDepositAmount, { from: accounts[1] });

    await SAMContract.buyNow(listingId, { from: accounts[1] });

    let account1Tokens = await SAMContract.addrTokens(accounts[1]);
    console.log("Escrow tokens of account 1 ", JSON.stringify(account1Tokens));
    assert.equal(account1Tokens.toString(), "0");

    let account1TokenIds = await LFGNFT.tokensOfOwner(accounts[1]);
    console.log("tokenIds of account 1 ", JSON.stringify(account1TokenIds));
    assert.equal(account1TokenIds[0], "1");

    account2TokenIds = await LFGNFT.tokensOfOwner(accounts[2]);
    console.log("tokenIds of account0 ", JSON.stringify(account2TokenIds));
    assert.equal(account2TokenIds[0], "3");

    let balanceOfAccount2 = await LFGToken.balanceOf(accounts[2]);
    console.log("Balance of account 2 ", balanceOfAccount2.toString());

    balanceOfAccount2 = await LFGToken.balanceOf(accounts[2]);
    console.log("Balance of account 2 ", balanceOfAccount2.toString());
    assert.equal(balanceOfAccount2.toString(), "59800000"); // 43800000 + 1600000

    listingResult = await SAMContract.listingOfAddr(accounts[2]);
    assert.equal(listingResult.length, 0);

    let balanceOfAccount6 = await LFGToken.balanceOf(accounts[6]);
    console.log("Balance of account 6 ", balanceOfAccount6.toString());
    assert.equal(balanceOfAccount6.toString(), "3600000"); // Because charged 10% royalties fee, so 4000000 becomes 3600000

    // Incresed revenue = 20000000 * 2.5% * 50% + 20000000 * 20% * 10% = 650000
    // Last step revenue is 547500, so total revenue is 547500 + 650000 = 1197500
    let revenueAmount = await SAMContract.revenueAmount();
    assert.equal(revenueAmount.toString(), "1197500");

    let revenueBalance = await LFGToken.balanceOf(revenueAddress);
    console.log("Revenue account balance ", revenueBalance.toString());
    assert.equal(revenueBalance.toString(), "1197500");
  });
});
