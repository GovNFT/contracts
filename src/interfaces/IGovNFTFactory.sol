// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

interface IGovNFTFactory {
    event GovNFTCreated(
        address indexed owner,
        address indexed artProxy,
        string name,
        string symbol,
        address indexed govNFT,
        uint256 govNFTCount
    );

    error NotAuthorized();
    error ZeroAddress();

    /// @notice Get the permissionless GovNFT contract created and owned by this factory
    function govNFT() external view returns (address);

    /// @notice Create a GovNFT contract
    /// @param _owner Owner of the GovNFT
    /// @param _artProxy Address of the art proxy
    /// @param _name Name of the GovNFT
    /// @param _symbol Symbol of the GovNFT
    /// @return Address of the created GovNFT
    function createGovNFT(
        address _owner,
        address _artProxy,
        string memory _name,
        string memory _symbol
    ) external returns (address);

    /// @notice View all created GovNFTs
    /// @return Array of GovNFTs
    function govNFTs() external view returns (address[] memory);

    /// @notice View if an address is a GovNFT contract created by this factory
    /// @param _govNFT Address of govNFT queried
    /// @return True if GovNFT, else false
    function isGovNFT(address _govNFT) external view returns (bool);

    /// @notice Get the count of created GovNFTs
    /// @return Count of created GovNFTs
    function govNFTsLength() external view returns (uint256);
}
