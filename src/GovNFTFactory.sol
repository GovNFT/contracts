// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IGovNFTFactory} from "./interfaces/IGovNFTFactory.sol";
import {GovNFTSplit} from "./extensions/GovNFTSplit.sol";

/// @title GovNFTFactory
/// @notice GovNFTFactory contract to create and keep track of GovNFTs
contract GovNFTFactory is IGovNFTFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev Array of deployed govNFTs
    EnumerableSet.AddressSet internal _registry;

    /// @inheritdoc IGovNFTFactory
    address public immutable govNFT;

    constructor(address _artProxy, string memory _name, string memory _symbol) {
        // Create permissionless GovNFT
        // @dev Permissionless GovNFT cannot Sweep Lock's tokens prior to Lock expiry
        govNFT = address(
            new GovNFTSplit({
                _owner: address(this),
                _artProxy: _artProxy,
                _name: _name,
                _symbol: _symbol,
                _earlySweepLockToken: false
            })
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
        string memory _symbol,
        bool _earlySweepLockToken
    ) external returns (address _govNFT) {
        if (_owner == address(this)) revert NotAuthorized();
        if (_artProxy == address(0)) revert ZeroAddress();
        _govNFT = address(
            new GovNFTSplit({
                _owner: _owner,
                _artProxy: _artProxy,
                _name: _name,
                _symbol: _symbol,
                _earlySweepLockToken: _earlySweepLockToken
            })
        );
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
