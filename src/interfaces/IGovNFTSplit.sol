// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import {IGovNFT} from "./IGovNFT.sol";

interface IGovNFTSplit is IGovNFT {
    /// @notice Splitting creates new Split NFTs from a given Parent NFT
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
    /// @return Returns token IDs of the new Split NFTs with the desired locks.
    function split(uint256 _from, SplitParams[] calldata _paramsList) external returns (uint256[] memory);
}
