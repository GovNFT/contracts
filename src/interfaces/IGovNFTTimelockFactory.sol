// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

interface IGovNFTTimelockFactory {
    /// Events
    event GovNFTTimelockCreated(
        address indexed owner,
        address indexed artProxy,
        string name,
        string symbol,
        uint256 timelock,
        address indexed govNFT,
        uint256 govNFTCount
    );

    /// Errors
    error NotAuthorized();
    error ZeroAddress();

    /// @notice Get the permissionless GovNFT contract created and owned by this factory
    function govNFT() external view returns (address);

    /// @notice Create a GovNFT contract
    /// @param _owner Owner of the GovNFT
    /// @param _artProxy Address of the art proxy
    /// @param _name Name of the GovNFT
    /// @param _symbol Symbol of the GovNFT
    /// @param _earlySweepLockToken Defines if Lock tokens can be Swept prior to lock expiry
    /// @param _timelock Timelock for the GovNFT
    /// @return _govNFT Address of the created GovNFT
    function createGovNFT(
        address _owner,
        address _artProxy,
        string memory _name,
        string memory _symbol,
        bool _earlySweepLockToken,
        uint256 _timelock
    ) external returns (address _govNFT);

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
