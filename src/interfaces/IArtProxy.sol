// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import {IGovNFT} from "./IGovNFT.sol";

interface IArtProxy {
    struct ConstructTokenURIParams {
        string lockTokenSymbol;
        uint8 lockTokenDecimals;
        address govNFT;
        string govNFTSymbol;
        uint256 tokenId;
        address lockToken;
        uint256 initialDeposit;
        uint256 vestingAmount;
        uint256 lockStart;
        uint256 lockEnd;
        uint256 cliff;
    }

    /// @notice Generate a SVG based on GovNFT metadata
    /// @param _tokenId Unique GovNFT identifier
    /// @return output SVG metadata as HTML tag
    function tokenURI(uint256 _tokenId) external view returns (string memory output);
}
