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

    /// @inheritdoc IGovNFTFactory
    address public immutable vaultImplementation;

    constructor(address _vaultImplementation, address _artProxy, string memory _name, string memory _symbol) {
        vaultImplementation = _vaultImplementation;
        // Create permissionless GovNFT
        // @dev Permissionless GovNFT cannot Sweep Lock's tokens prior to Lock expiry
        govNFT = address(
            new GovNFTSplit({
                _owner: address(this),
                _artProxy: _artProxy,
                _vaultImplementation: _vaultImplementation,
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
                _vaultImplementation: vaultImplementation,
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
    function govNFTs(uint256 _start, uint256 _end) external view returns (address[] memory _govNFTs) {
        uint256 length = _registry.length();
        _end = _end <= length ? _end : length;
        _govNFTs = new address[](_end - _start);
        for (uint256 i = 0; i < _end - _start; i++) {
            _govNFTs[i] = _registry.at(i + _start);
        }
    }

    /// @inheritdoc IGovNFTFactory
    function govNFTByIndex(uint256 _index) external view returns (address) {
        return _registry.at(_index);
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
