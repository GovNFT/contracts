import * as dotenv from "dotenv";
import * as tdly from "@tenderly/hardhat-tenderly";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";

dotenv.config();
tdly.setup({ automaticVerifications: true });

export default {
  defaultNetwork: "tenderly",
  networks: {
    hardhat: {},
    devnet: {
      url: `https://rpc.vnet.tenderly.co/devnet/${process.env.TENDERLY_DEVNET_TEMPLATE}/${process.env.TENDERLY_DEVNET_ID}`,
      accounts: [`${process.env.PRIVATE_KEY_DEPLOY}`],
    },
    tenderly: {
      url: `https://rpc.tenderly.co/fork/${process.env.TENDERLY_FORK_ID}`,
      accounts: [`${process.env.PRIVATE_KEY_DEPLOY}`],
    },
  },
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  tenderly: {
    username: "velodrome-finance",
    project: "v2",
    privateVerification: false,
  },
  paths: {
    sources: "./src",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  typechain: {
    outDir: "artifacts/types",
    target: "ethers-v5",
  },
};
