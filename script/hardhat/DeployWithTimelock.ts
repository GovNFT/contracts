import { Contract } from "@ethersproject/contracts";
import { ethers } from "hardhat";
import { Libraries } from "hardhat/types";
import { join } from "path";
import { writeFile } from "fs/promises";
import { GovNFTTimelockFactory } from "../../artifacts/types";

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
  const govNFTTimelockFactory = await deploy<GovNFTTimelockFactory>(
    "GovNFTTimelockFactory",
    undefined,
    "0x0000000000000000000000000000000000000000", //TODO veArtProxy contract address
    "GovNFT: NFT for vested distribution of (governance) tokens",
    "GOVNFT",
    3600,
  );
  console.log(
    `GovNFTTimelockFactory deployed to ${govNFTTimelockFactory.address}`,
  );

  interface DeployOutput {
    GovNFTTimelockFactory: string;
  }

  const output: DeployOutput = {
    GovNFTTimelockFactory: govNFTTimelockFactory.address,
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
