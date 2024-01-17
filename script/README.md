## Deploy GovNFT

### Environment setup

`cp .env.sample .env` and set the environment variables. `PRIVATE_KEY_DEPLOY` is the private key
used in contract deployment.

```
source .env
```

### Deployment

#### Optimism

```
forge script script/Deploy.s.sol:Deploy --broadcast --slow --rpc-url optimism --verify -vvvv
```

#### Tenderly

Foundry does not automatically verify contracts within Tenderly. To test with tenderly, you will
need to use hardhat. Specifically, you will need to modify `hardhat.config.ts` with your correct
`tenderly` object. If you are using Tenderly devnet, you will need to set `TENDERLY_DEVNET_TEMPLATE`
and `TENDERLY_DEVNET` in the .env. `TENDERLY_DEVNET_TEMPLATE` is the name of the devnet template you
are using. `TENDERLY_DEVNET` is the auto-generated key for the template when you select "Spawn
DevNet" within the template. It will look something like `d81265d8-1bad-457c-13da-0a51e815ae54`. For
more information on Tenderly devnets, see [here](https://docs.tenderly.co/devnets/intro-to-devnets).
For a forked environment instead of a devnet, you will need to set `TENDERLY_FORK_ID` in the .env.

```
yarn install
yarn hardhat compile
yarn hardhat run script/hardhat/Deploy.ts --network devnet
```

Note that the output file is hardcoded within `Deploy.ts` to `Tenderly.json`.

For additional support with Tenderly deployment, see their
[docs](https://github.com/Tenderly/hardhat-tenderly/tree/master/packages/tenderly-hardhat).

#### Other chains

Note that if deploying to a chain other than Optimism, if you have a different .env variable name
used for `RPC_URL`, `SCAN_API_KEY` and `ETHERSCAN_VERIFIER_URL`, you will need to use the
corresponding chain name by also updating `foundry.toml`.
