// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IGovNFTTimelockFactory} from "./interfaces/IGovNFTTimelockFactory.sol";
import {GovNFTTimelock} from "./extensions/GovNFTTimelock.sol";

/// @title GovNFTTimelockFactory
/// @notice GovNFTFactoryTimelock contract to create and keep track of GovNFTs with timelock
contract GovNFTTimelockFactory is IGovNFTTimelockFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev Array of deployed govNFTs
    EnumerableSet.AddressSet internal _registry;

    /// @inheritdoc IGovNFTTimelockFactory
    address public immutable govNFT;

    /// @inheritdoc IGovNFTTimelockFactory
    address public immutable vaultImplementation;

    constructor(
        address _vaultImplementation,
        address _artProxy,
        string memory _name,
        string memory _symbol,
        uint256 _timelock
    ) {
        vaultImplementation = _vaultImplementation;
        // Create permissionless GovNFT
        // @dev Permissionless GovNFT cannot Sweep Lock's tokens prior to Lock expiry
        govNFT = address(
            new GovNFTTimelock({
                _owner: address(this),
                _artProxy: _artProxy,
                _vaultImplementation: _vaultImplementation,
                _name: _name,
                _symbol: _symbol,
                _earlySweepLockToken: false,
                _timelock: _timelock
            })
        );
        _registry.add(govNFT);
        emit GovNFTTimelockCreated({
            owner: address(this),
            artProxy: _artProxy,
            name: _name,
            symbol: _symbol,
            timelock: _timelock,
            govNFT: govNFT,
            govNFTCount: _registry.length()
        });
    }

    /// @inheritdoc IGovNFTTimelockFactory
    function createGovNFT(
        address _owner,
        address _artProxy,
        string memory _name,
        string memory _symbol,
        bool _earlySweepLockToken,
        uint256 _timelock
    ) external returns (address _govNFT) {
        if (_owner == address(this)) revert NotAuthorized();
        if (_artProxy == address(0)) revert ZeroAddress();
        _govNFT = address(
            new GovNFTTimelock({
                _owner: _owner,
                _artProxy: _artProxy,
                _vaultImplementation: vaultImplementation,
                _name: _name,
                _symbol: _symbol,
                _earlySweepLockToken: _earlySweepLockToken,
                _timelock: _timelock
            })
        );
        _registry.add(_govNFT);
        emit GovNFTTimelockCreated({
            owner: _owner,
            artProxy: _artProxy,
            name: _name,
            symbol: _symbol,
            timelock: _timelock,
            govNFT: _govNFT,
            govNFTCount: _registry.length()
        });
    }

    /// @inheritdoc IGovNFTTimelockFactory
    function govNFTs() external view returns (address[] memory) {
        return _registry.values();
    }

    /// @inheritdoc IGovNFTTimelockFactory
    function govNFTs(uint256 _start, uint256 _end) external view returns (address[] memory _govNFTs) {
        uint256 length = _registry.length();
        _end = _end <= length ? _end : length;
        _govNFTs = new address[](_end - _start);
        for (uint256 i = 0; i < _end - _start; i++) {
            _govNFTs[i] = _registry.at(i + _start);
        }
    }

    /// @inheritdoc IGovNFTTimelockFactory
    function govNFTByIndex(uint256 _index) external view returns (address) {
        return _registry.at(_index);
    }

    /// @inheritdoc IGovNFTTimelockFactory
    function isGovNFT(address _govNFT) external view returns (bool) {
        return _registry.contains(_govNFT);
    }

    /// @inheritdoc IGovNFTTimelockFactory
    function govNFTsLength() external view returns (uint256) {
        return _registry.length();
    }
}
