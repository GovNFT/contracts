import { Contract } from "@ethersproject/contracts";
import { ethers } from "hardhat";
import { Libraries } from "hardhat/types";
import { join } from "path";
import { writeFile } from "fs/promises";
import { GovNFTTimelockFactory, ArtProxy, Vault } from "../../artifacts/types";

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
  const vaultImplementation = await deploy<Vault>("Vault", undefined);
  console.log(
    `Vault Implementation deployed to ${vaultImplementation.address}`,
  );
  const artProxy = await deploy<ArtProxy>("ArtProxy", undefined);
  console.log(`ArtProxy deployed to ${artProxy.address}`);
  const govNFTTimelockFactory = await deploy<GovNFTTimelockFactory>(
    "GovNFTTimelockFactory",
    undefined,
    vaultImplementation.address,
    artProxy.address,
    "GovNFT: NFT for vested distribution of (governance) tokens",
    "GOVNFT",
    3600,
  );
  console.log(
    `GovNFTTimelockFactory deployed to ${govNFTTimelockFactory.address}`,
  );

  interface DeployOutput {
    VaultImplementation: string;
    ArtProxy: string;
    GovNFTTimelockFactory: string;
  }

  const output: DeployOutput = {
    VaultImplementation: vaultImplementation.address,
    ArtProxy: artProxy.address,
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
