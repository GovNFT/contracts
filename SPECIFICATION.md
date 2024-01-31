# GovNFT Specification

GovNFT is a protocol for storing ERC-20 tokens under a vesting curve using ERC-721-based NFTs.

## Protocol Upgradability

The GovNFT contract is immutable. While new versions can be deployed, existing deployments will live indefinitely.

## Contracts

### GovNFT

Built upon OpenZeppelin's ERC721, this contract manages the vesting of ERC-20 tokens, represented as NFTs.
Note: This contract does not support the vesting of ERC-20 tokens that allow fees on transfer.

#### Create Lock

Enables the creation of an NFT that locks ERC-20 tokens and vests them over time to specified recipients.
Transfers the specified amount of ERC-20 tokens from the caller to a dedicated Vault and mints an NFT.
Allows to set parameters like:

- ERC-20 token address
- recipient address
- total token amount
- cliff length
- start time
- end time

#### Claiming Tokens

Allows recipients to claim vested tokens as they become available.
Determined by duration, start time, and cliff period, as specified during the Lock creation.

#### Splitting

The split function takes a parent NFT `from` and splits it into another NFT, that will be referred to as `tokenId`.

Calling `split` requires the following arguments:

- Address of the new NFT's beneficiary;
- ID of the parent NFT to be split;
- Amount to be vested in the new Split NFT;
- Timestamp parameters to be set on the Split NFT (i.e.: start, end and cliff length);

After a `split` is performed:

- The `from` NFT will only vest `locked - amount` tokens;
- `tokenId` NFT will be minted with `amount` locked tokens to be vested to the given `beneficiary`.

#### Delegation

Allows recipients to actively participate in governance delegation, even for tokens that are not claimed.
Key points:

- Only for ERC-20 tokens that have the `delegate` function implemented.
- The recipient calls the delegate function, specifying the delegatee's address.

#### Sweeping Airdropped Tokens

Airdrop Sweeping is designed to manage tokens that are deposited into the Lock outside the original vesting schedule, typically through airdrops.
The process involves the ability to "sweep" or transfer these additional tokens to a specified recipient.

### Vault

Each NFT is an exclusive owner of a Vault (where the ERC-20 tokens are actually held):

- allowing the GovNFT to withdraw vested tokens to the recipient
- delegate their voting rights while tokens are locked, if the stored tokens possess governance capabilities
- sweeping airdropped from the vault to a specified receiver.
