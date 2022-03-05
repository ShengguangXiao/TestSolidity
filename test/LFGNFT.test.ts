const {assert, expect} = require("chai");
const hre = require("hardhat");
const {web3} = require("hardhat");
const LFGNFTArt = hre.artifacts.require("LFGNFT");
const BN = require("bn.js");
const {createImportSpecifier} = require("typescript");

describe("LFGNFT", function () {
  let LFGNFT = null;
  let NftAirdrop = null;
  let accounts = ["", ""],
    minter;

  before("Deploy contract", async function () {
    try {
      [accounts[0], accounts[1], minter] = await web3.eth.getAccounts();
      LFGNFT = await LFGNFTArt.new();
    } catch (err) {
      console.log(err);
    }
  });

  it("test NFT Royalties", async function () {
    await LFGNFT.mint(1, accounts[1], {from: minter} );
    const nftBalance = await LFGNFT.balanceOf(accounts[1]);
    console.log("nftBalance ", nftBalance.toString());

    let account1TokenIds = await LFGNFT.tokensOfOwner(accounts[1]);
    console.log("tokenIds of account1 ", JSON.stringify(account1TokenIds));

    let royaltyInfo = await LFGNFT.royaltyInfo(account1TokenIds[0], 10000);
    console.log("royaltyInfo ", JSON.stringify(royaltyInfo));

    // Before set royalty, it should be 0
    assert.equal(royaltyInfo["royaltyAmount"], "0");

    // set 10% royalty
    await LFGNFT.setRoyalty(account1TokenIds[0], accounts[1], 1000, {from: minter});
  
    royaltyInfo = await LFGNFT.royaltyInfo(account1TokenIds[0], 10000);
    console.log("royaltyInfo ", JSON.stringify(royaltyInfo));

    assert.equal(royaltyInfo["receiver"], accounts[1]);
    assert.equal(royaltyInfo["royaltyAmount"], "1000");
  });

  it("test NFT Royalties", async function () {
    await expect(
      LFGNFT.mint(11, accounts[1], {from: minter} )
    ).to.be.revertedWith("NFT: cannot mint over max batch quantity");

    await LFGNFT.setMaxBatchQuantity(20, {from: accounts[0]});

    let getMaxBatchQuantity = await LFGNFT.maxBatchQuantity();
    assert.equal(getMaxBatchQuantity.toString(), "20");

    await LFGNFT.mint(11, accounts[1], {from: minter} );
  });  
});
