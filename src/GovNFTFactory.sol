// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IGovNFTFactory} from "./interfaces/IGovNFTFactory.sol";
import {GovNFTSplit} from "./extensions/GovNFTSplit.sol";

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
        govNFT = address(
            new GovNFTSplit({_owner: address(this), _artProxy: _artProxy, _name: _name, _symbol: _symbol})
        );
        _registry.add(govNFT);
        emit GovNFTCreated({
            owner: address(this),
            artProxy: _artProxy,
            name: _name,
            symbol: _symbol,
            govNFT: govNFT,
            govNFTCount: _registry.length()
        });
    }

    /// @inheritdoc IGovNFTFactory
    function createGovNFT(
        address _owner,
        address _artProxy,
        string memory _name,
        string memory _symbol
    ) external returns (address _govNFT) {
        if (_owner == address(this)) revert NotAuthorized();
        if (_artProxy == address(0)) revert ZeroAddress();
        _govNFT = address(new GovNFTSplit({_owner: _owner, _artProxy: _artProxy, _name: _name, _symbol: _symbol}));
        _registry.add(_govNFT);
        emit GovNFTCreated({
            owner: _owner,
            artProxy: _artProxy,
            name: _name,
            symbol: _symbol,
            govNFT: _govNFT,
            govNFTCount: _registry.length()
        });
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
