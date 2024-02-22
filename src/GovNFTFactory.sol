// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import {GovNFTSplit} from "./extensions/GovNFTSplit.sol";
import {IGovNFTFactory} from "./interfaces/IGovNFTFactory.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title Velodrome GovNFTFactory
/// @author velodrome.finance, @airtoonricardo, @pedrovalido
/// @notice GovNFTFactory contract to create and keep track of GovNFTs
contract GovNFTFactory is IGovNFTFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev Array of deployed govNFTs
    EnumerableSet.AddressSet internal _registry;

    /// @inheritdoc IGovNFTFactory
    address public immutable govNFT;

    constructor(address _artProxy, string memory _name, string memory _symbol) {
        // Create permissionless GovNFT
        govNFT = address(new GovNFTSplit(address(this), _artProxy, _name, _symbol));
        _registry.add(address(govNFT));
        emit GovNFTCreated(address(this), _artProxy, _name, _symbol, govNFT, _registry.length());
    }

    /// @inheritdoc IGovNFTFactory
    function createGovNFT(
        address _owner,
        address _artProxy,
        string memory _name,
        string memory _symbol
    ) external returns (address) {
        if (_owner == address(this)) revert NotAuthorized();
        if (_artProxy == address(0)) revert ZeroAddress();
        address _govNFT = address(new GovNFTSplit(_owner, _artProxy, _name, _symbol));
        _registry.add(_govNFT);
        emit GovNFTCreated(_owner, _artProxy, _name, _symbol, _govNFT, _registry.length());

        return address(_govNFT);
    }

    /// @inheritdoc IGovNFTFactory
    function govNFTs() external view returns (address[] memory) {
        return _registry.values();
    }

    /// @inheritdoc IGovNFTFactory
    function isGovNFT(address _govNFT) external view returns (bool) {
        return _registry.contains(_govNFT);
    }

    /// @inheritdoc IGovNFTFactory
    function govNFTsLength() external view returns (uint256) {
        return _registry.length();
    }
}
