// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import {IGovNFT} from "./IGovNFT.sol";

interface IGovNFTTimelock is IGovNFT {
    /// Errors
    error AlreadyIntendedFrozen();
    error AlreadyIntendedUnfrozen();
    error FrozenToken();
    error UnfrozenToken();

    /// Events
    event Freeze(uint256 indexed tokenId);
    event Unfreeze(uint256 indexed tokenId);

    struct Frozen {
        uint40 timestamp;
        bool isFrozen;
    }

    /// @notice Returns the timelock for the Split
    function timelock() external view returns (uint256);

    /// @notice Returns the Frozen information for a given token ID
    /// @param _tokenId Token Id from which the info will be fetched
    /// @return Frozen Information for the given token ID
    function frozenState(uint256 _tokenId) external view returns (Frozen memory);

    /// @notice Freezes a token
    /// @param _tokenId The token to freeze
    function freeze(uint256 _tokenId) external;

    /// @notice Unfreezes a token
    /// @param _tokenId The token to unfreeze
    function unfreeze(uint256 _tokenId) external;

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
