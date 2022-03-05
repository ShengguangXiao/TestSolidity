const {expect} = require("chai");
const hre = require("hardhat");
const {web3} = require("hardhat");
const LFGFireNFTArt = hre.artifacts.require("LFGFireNFT");
const NftAirdropArt = hre.artifacts.require("NftAirdrop");
const BN = require("bn.js");
const {createImportSpecifier} = require("typescript");

describe("NftAirdrop", function () {
  let LFGFireNFT = null;
  let NftAirdrop = null;
  let accounts = ["", ""],
    minter;

  const airDropNftAmount = 2;

  before("Deploy contract", async function () {
    try {
      [accounts[0], accounts[1], minter] = await web3.eth.getAccounts();
      LFGFireNFT = await LFGFireNFTArt.new();
      NftAirdrop = await NftAirdropArt.new(LFGFireNFT.address);
      await LFGFireNFT.setMinter(NftAirdrop.address, true);
    } catch (err) {
      console.log(err);
    }
  });

  it("test claim NFT method", async function () {
    const today = Math.round(new Date() / 1000);
    await hre.network.provider.send("evm_setNextBlockTimestamp", [today + 1000]);
    await hre.network.provider.send("evm_mine");
    await NftAirdrop.addWhitelists([accounts[1]], [airDropNftAmount]);

    let minterResult = await LFGFireNFT.minters(NftAirdrop.address);
    console.log("Get minter result ", minterResult.toString());

    const whitelistInfo = await NftAirdrop.whitelistPools(accounts[1]);
    expect(new BN(whitelistInfo.nftAmount).toString()).to.equal(airDropNftAmount.toString());
    expect(new BN(whitelistInfo.distributedAmount).toString()).to.equal("0");

    await NftAirdrop.claimDistribution({from: accounts[1]});
    const whitelistInfoAfter = await NftAirdrop.whitelistPools(accounts[1]);
    expect(new BN(whitelistInfoAfter.nftAmount).toString()).to.equal(airDropNftAmount.toString());
    expect(new BN(whitelistInfoAfter.distributedAmount).toString()).to.equal(airDropNftAmount.toString());

    const nftBalance = await LFGFireNFT.balanceOf(accounts[1]);
    console.log("nftBalance ", nftBalance.toString());
    expect(new BN(nftBalance).toString()).to.equal(airDropNftAmount.toString());
  });
});
