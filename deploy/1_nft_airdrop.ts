import "@nomiclabs/hardhat-ethers";

import { Contract, ContractFactory } from "ethers";
import { ethers } from "hardhat"; // Optional (for `node <script>`)

async function deploy() {

  const LFGNFT: ContractFactory = await ethers.getContractFactory("LFGNFT");
  const lfgNft: Contract = await LFGNFT.deploy();
  await lfgNft.deployed();
  console.log("lfgNft deployed to: ", lfgNft.address);

  
  const NftAirdrop: ContractFactory = await ethers.getContractFactory(
    "NftAirdrop"
  );

  const nftAirdrop: Contract = await NftAirdrop.deploy(lfgNft.address);
  await nftAirdrop.deployed();
  console.log("NftAirdrop deployed to: ", nftAirdrop.address);

  
}

async function main(): Promise<void> {
  await deploy();
}

main()
  .then(() => process.exit(0))
  .catch((error: Error) => {
    console.error(error);
    process.exit(1);
  });
