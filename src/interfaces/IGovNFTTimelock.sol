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
}
