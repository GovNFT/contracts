// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;
import {IGovNFT} from "./IGovNFT.sol";

interface IGovNFTTimelock is IGovNFT {
    /// Errors
    error SplitTooSoon();

    /// Events
    event CommitSplit(
        uint256 indexed from,
        address indexed recipient,
        uint256 splitAmount,
        uint256 startTime,
        uint256 endTime,
        string description
    );

    /// @dev Split Proposal Information for an NFT:
    ///      `timestamp` Timestamp of the Split Proposal
    ///      `pendingSplits` Array of Split parameters to be used when splitting the given NFT
    struct SplitProposal {
        uint256 timestamp;
        SplitParams[] pendingSplits;
    }

    /// @notice Returns the timelock for the Split
    function timelock() external view returns (uint256);

    /// @notice Returns the Split Proposal information for the given `_tokenId`
    /// @param _tokenId Lock Token Id with pending Split Proposal
    /// @return Split Proposal information to be used to finalize the Split
    function proposedSplits(uint256 _tokenId) external view returns (SplitProposal memory);

    /// @notice Commits the intention of splitting a given Parent NFT, given the parameters
    /// @dev After a Split is finalized, new Split NFTs are minted from a given Parent NFT
    /// - The Parent NFT will have `locked(from) - sum` tokens to be vested,
    ///   where `sum` is the sum of all tokens to be vested in the Split Locks
    /// - Each Split NFT will vest `params.amount` tokens
    /// - The new NFTs will also use the new recipient, cliff, start and end timestamps from `params`
    /// @dev     Callable by owner and approved operators
    ///          Unclaimed tokens vested on the old `_from` NFT are still claimable after split
    ///          `params.start` cannot be lower than old start or block.timestamp
    ///          `params.end` cannot be lower than the old end
    ///          `params.cliff` has to end at the same time or after the old cliff
    /// @param _from Token ID of the NFT to be split
    /// @param _paramsList List of SplitParams structs containing all the parameters needed to split a lock
    function commitSplit(uint256 _from, SplitParams[] calldata _paramsList) external;

    /// @notice Finalizes the Splits previously proposed on the given NFT
    /// @param _from Token ID of the NFT to be split
    /// @return _splitTokenIds Returns token IDs of the new Split NFTs with the desired locks.
    function finalizeSplit(uint256 _from) external returns (uint256[] memory _splitTokenIds);
}
