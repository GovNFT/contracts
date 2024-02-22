// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

interface IArtProxy {
    /// @notice Generate a SVG based on GovNFT metadata
    /// @param _tokenId Unique GovNFT identifier
    /// @return output SVG metadata as HTML tag
    function tokenURI(uint256 _tokenId) external view returns (string memory output);
}
