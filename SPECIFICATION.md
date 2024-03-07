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

Creating a lock is only allowed by the contract's owner, unless the GovNFT contract is owned by the factory (in that case anyone can create a lock).

#### Claiming Tokens

Allows recipients to claim vested tokens as they become available.
Determined by duration, start time, and cliff period, as specified during the Lock creation.

#### Delegation

Allows recipients to actively participate in governance delegation, even for tokens that are not claimed.
Key points:

- Only for ERC-20 tokens that have the `delegate` function implemented.
- The recipient calls the delegate function, specifying the delegatee's address.

#### Sweeping Airdropped Tokens

Airdrop Sweeping is designed to manage tokens that are deposited into the Lock outside the original vesting schedule, typically through airdrops.
The process involves the ability to "sweep" or transfer these additional tokens to a specified recipient.
If the airdrop is the same as the lock's token, the sweeping is restricted depending on the `earlySweepLockToken` flag. If false, these tokens can only be swept after the lock's expired (can be swept any time otherwise).

### GovNFTSplit

#### Splitting

The split function takes a parent NFT `from` and splits it into another NFT, that will be referred to as `to`.

Calling `split` requires the following arguments:

- Address of the new NFT's beneficiary;
- ID of the parent NFT to be split;
- Amount to be vested in the new Split NFT;
- Timestamp parameters to be set on the Split NFT (i.e.: start, end and cliff length);

After a `split` is performed:

- The `from` NFT will only vest `locked - amount` tokens;
- The `to` NFT will be minted with `amount` locked tokens to be vested to the given `beneficiary`.

Additionally, there is the option to batch split the parent NFT `from` into several `to` NFTs, providing an array of split parameters.

### GovNFTTimelock

#### Splitting

Implements the splitting functionality in 2 steps:

- propose a split
- finalize a proposed split after the timelock period has ended

### Vault

Each NFT is an exclusive owner of a Vault (where the ERC-20 tokens are actually held):

- allowing the GovNFT to withdraw vested tokens to the recipient
- delegate their voting rights while tokens are locked, if the stored tokens possess governance capabilities
- sweeping airdropped tokens from the vault to a specified receiver.

### GovNFTFactory

Facilitates the creation and tracking of deployed GovNFTSplits. Creating a GovNFT requires the following arguments:

- owner who will be allowed to create locks
- address of the artProxy to be used for the token URI
- name and symbol
- boolean to allow early sweeps of aidropped lock tokens

Upon the deployment of the factory, a single permissionless GovNFT meant for public use is created and owned by the factory (anyone can create a lock in this case).

### GovNFTTimelockFactory

Similarly to GovNFTFactory, it creates and keeps track of GovNFTTimelocks.
When creating a GovNFTTimelock, a timelock period is passed as a parameter (time to wait between proposal of a split and its finality).
