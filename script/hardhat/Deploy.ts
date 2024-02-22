import { Contract } from "@ethersproject/contracts";
import { ethers } from "hardhat";
import { Libraries } from "hardhat/types";
import { join } from "path";
import { writeFile } from "fs/promises";
import { GovNFTFactory } from "../../artifacts/types";

export async function deploy<Type>(
  typeName: string,
  libraries?: Libraries,
  ...args: any[]
): Promise<Type> {
  const ctrFactory = await ethers.getContractFactory(typeName, { libraries });

  const ctr = (await ctrFactory.deploy(...args)) as unknown as Type;
  await (ctr as unknown as Contract).deployed();
  return ctr;
}

async function main() {
  const govNFTFactory = await deploy<GovNFTFactory>(
    "GovNFTFactory",
    undefined,
    "0x0000000000000000000000000000000000000000", //TODO veArtProxy contract address
    "GovNFT",
    "GovNFT",
  );
  console.log(`GovNFTFactory deployed to ${govNFTFactory.address}`);

  interface DeployOutput {
    GovNFTFactory: string;
  }

  const output: DeployOutput = {
    GovNFTFactory: govNFTFactory.address,
  };

  const outputDirectory = "script/constants/output";
  const outputFile = join(process.cwd(), outputDirectory, "Tenderly.json");

  try {
    await writeFile(outputFile, JSON.stringify(output, null, 2));
  } catch (err) {
    console.error(`Error writing output file: ${err}`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
