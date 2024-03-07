# GovNFT

GovNFT is a protocol that facilitates the secure and efficient vesting of ERC-20 tokens through governance NFTs (GovNFTs).

See `SPECIFICATION.md` for more detail.

## Protocol Overview

### Contracts

| Filename                    | Description                                                                                                                                    |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `GovNFT.sol`                | Abstract contract that manages the vesting process of ERC-20 tokens, represented as ERC-721 NFTs, including creating nfts and handling claims. |
| `GovNFTSplit.sol`           | Inherits from GovNFT and implements the split functionality.                                                                                   |
| `GovNFTTimelock.sol`        | Inherits from GovNFT and implements the split functionality with timelock.                                                                     |
| `Vault.sol`                 | Stores ERC-20 tokens for nfts, enabling delegation of governance tokens and fund management through the GovNFT contract.                       |
| `GovNFTFactory.sol`         | Used to create and keep track of deployed GovNFTSplit instances.                                                                               |
| `GovNFTTimelockFactory.sol` | Used to create and keep track of deployed GovNFTTimelock instances.                                                                            |

## Testing

This repository uses Foundry for testing and deployment.

Foundry Setup

```
forge install
forge build
forge test
```

## Lint

`yarn format` to run prettier.

## Deployment

See `script/README.md` for more detail.

## Security

TODO: add audit info here

## Access Control

This is a list of all permissions in GovNFT, sorted by the contract they are stored in.

### GovNFT

- Lock Recipient and Approved Operators

  - can claim vested tokens
  - can delegate the voting power of all unclaimed and locked tokens
  - can sweep airdropped tokens to a recipient
  - can split its lock to another entity

- GovNFT owner
  - when owner is not the factory, only the owner can create locks
  - when the owner is the factory, anyone can create locks

### Vault

The GovNFT contract is the only one allowed to interact with the vault.
The GovNFT contract can:

- withdraw the vault's token
- delegate the vault's tokens to a delegatee
- sweep airdropped tokens to a recipient

## Deployment

GovNFT - TODO: add deployed address
