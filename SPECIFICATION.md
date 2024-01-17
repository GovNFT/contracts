# GovNFT Specification

GovNFT is a protocol for storing ERC-20 tokens under a vesting curve using ERC-721-based NFTs.

## Protocol Upgradability

The GovNFT contract is immutable. While new versions can be deployed, existing deployments will live indefinitely.

## Contracts

### GovNFT

Built upon OpenZeppelin's ERC721, this contract manages the vesting of ERC-20 tokens, represented as NFTs.

#### Create NFT

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
Determined by duration, start time, and cliff period, as specified during the NFT creation.

#### NFT Splitting

These split functions take a parent NFT `from` as an argument and splits it into another NFT, that will be referred to as `tokenId`.

After each `split(beneficiary, from, amount)`:

- `from` NFT will have its `locked` value decreased, and will instead only vest `locked - amount` tokens;
- And `tokenId` NFT will be minted with `amount` locked tokens to vest. This NFT is then transferred `beneficiary`,
  who will be able to claim any of its vested tokens.

Besides the amount to be vested, a split can also change the NFT's vesting timestamps in the following cases:

- If the `start` timestamp from the `from` NFT is already older than the current `block.timestamp`, the new NFT will
  have by default `block.timestamp` as their `start` value, in order to not create any NFTs that started their vesting in the past;
- If the `cliff` period from the `from` token has already ended (which means that vesting has already started for
  the parent NFT), the new cliff will be set to 0 on both NFTs, letting them both continue their initial vesting;
- The `end` timestamp remains the same for both tokens.
  Note: The `from` token will still contain any unclaimed tokens after being split.

Additionally, there is a second split function `splitTo(beneficiary, from, amount, start, end, cliff)`:

- This behaves similarly to the first one, except that it also accepts timestamp
  parameters (i.e.: start, end and cliff) to update how the vesting will be performed on `tokenId`,
  in case its period should be extended. Note that this does not change the timestamps set on parent NFT `from`.

Calling `splitTo` the following are required:

- The `start` timestamp should be greater than or equal to both the `start` on the original `from` NFT
  and `block.timestamp`;
- The `end` timestamp should also be greater than or equal to the original `end` on the`from` NFT;
- The end of the cliff period (`start + cliff`) should always be greater or equal to the end of the original cliff.

#### Delegation

Allows recipients to actively participate in governance delegation, even for tokens that are not claimed.
Key points:

- Only for ERC-20 tokens that have the `delegate` function implemented.
- The delegated amount will default to the balance of tokens in the NFT vault
- The recipient calls the delegate function, specifying the delegatee's address.

#### Sweeping Airdropped Tokens

Airdrop Sweeping is designed to manage tokens that are deposited into the NFT outside the original vesting schedule, typically through airdrops.
The process involves the ability to "sweep" or transfer these additional tokens to a specified recipient.

### Vault

Each NFT is an exclusive owner of a Vault (where the ERC-20 tokens are actually held):

- allowing the GovNFT to withdraw vested tokens to the recipient
- delegate their voting rights while tokens are locked, if the stored tokens possess governance capabilities
- sweeping airdropped from the vault to a specified receiver.
