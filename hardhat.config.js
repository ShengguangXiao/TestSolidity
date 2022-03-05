//import { resolve } from "path";
require("dotenv").config();

// import { HardhatUserConfig } from "hardhat/config";
// import { NetworkUserConfig } from "hardhat/types";

require("@nomiclabs/hardhat-waffle");
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-ethers");
require("@nomiclabs/hardhat-truffle5");
require("hardhat-typechain");

//if (!process.env.MNEMONICS) throw new Error("MNEMONICS missing from .env file");
if (!process.env.MUMBAI_PRIVKEY)
  throw new Error("RINKEBY_PRIVKEY missing from .env file");
// if (!process.env.MAINNET_PRIVKEY)
//   throw new Error("MAINNET_PRIVKEY missing from .env file");

//const mnemonics = process.env.MNEMONICS;

module.exports = {
  defaultNetwork: "localhost",
  networks: {
      localhost: {
        url: `http://127.0.0.1:8545`,
    },

    // hardhat: {
    //   forking: {
    //     url: `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_KEY}`,
    //     blockNumber: 11589707,
    //   },
    // },
    // mumbai: {
    //   chainId: 80001,
    //   url: `https://polygon-mumbai.g.alchemy.com/v2/${process.env.ALCHEMY_KEY}`,
    //   accounts: [process.env.MUMBAI_PRIVKEY],
    // },
    // matic: {
    //   chainId: 137,
    //   url: "https://polygon-rpc.com",
    //   accounts: [process.env.MAINNET_PRIVKEY],
    //   gasPrice: 8000000000,
    // },
    bsctest: {
      accounts: [process.env.MUMBAI_PRIVKEY || ""],
      chainId: 97,
      url: "https://data-seed-prebsc-1-s1.binance.org:8545",
      timeout: 99999,
      gasPrice: 20e9,
      gas: 35e5,
    },
    // bsc: {
    //   accounts: [process.env.MAINNET_PRIVKEY || ""],
    //   chainId: 56,
    //   url: "https://bsc-dataseed1.ninicoin.io/",
    //   timeout: 999999,
    //   gasPrice: 20e9,
    //   gas: 35e5,
    // },
  },
  etherscan: {
    apiKey: process.env.BSCSCAN_API
  },
  paths: {
    artifacts: "./artifacts",
    cache: "./cache",
    sources: "./contracts",
    tests: "./tests",
  },
  solidity: {
    compilers: [
      {
        version: "0.8.9",
        settings: {},
      },
      {
        version: "0.6.12",
        settings: {},
      },
    ],
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  mocha: {
    timeout: 2000000000,
  },
  typechain: {
    outDir: "types/contracts",
    target: "truffle-v5",
  },
};

//export default config;
