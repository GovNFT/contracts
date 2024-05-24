// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import {IGovNFTTimelock} from "../interfaces/IGovNFTTimelock.sol";
import {GovNFT} from "../GovNFT.sol";
import {IGovNFT} from "../interfaces/IGovNFT.sol";

/// @title GovNFTTimelock
/// @notice GovNFT implementation that vests ERC-20 tokens to a given address, in the form of an ERC-721
/// @notice Tokens are vested over a determined period of time, as soon as the Cliff period ends
/// @dev    This contract extends the original GovNFT implementation to include a timelock mechanism,
///         in order allow the transfer of NFTs with a fixed value.
contract GovNFTTimelock is GovNFT, IGovNFTTimelock {
    /// @dev Duration of the timelock period
    uint256 public immutable timelock;

    /// @dev tokenId => Frozen state information
    mapping(uint256 => Frozen) internal _frozenState;

    constructor(
        address _owner,
        address _artProxy,
        address _vaultImplementation,
        string memory _name,
        string memory _symbol,
        bool _earlySweepLockToken,
        uint256 _timelock
    ) GovNFT(_owner, _artProxy, _vaultImplementation, _name, _symbol, _earlySweepLockToken) {
        timelock = _timelock;
    }

    /// @dev Modifier to check if the token is Unfrozen
    /// @param _tokenId Token ID to check
    /// @notice Reverts if the token is frozen
    modifier onlyUnfrozen(uint256 _tokenId) {
        if (_frozenState[_tokenId].isFrozen) {
            revert FrozenToken();
        }
        _;
    }

    /// @inheritdoc IGovNFTTimelock
    function frozenState(uint256 _tokenId) external view returns (Frozen memory) {
        return _frozenState[_tokenId];
    }

    /// @inheritdoc IGovNFTTimelock
    function freeze(uint256 _tokenId) external nonReentrant {
        _checkAuthorized({owner: _ownerOf(_tokenId), spender: msg.sender, tokenId: _tokenId});

        Frozen storage frozen = _frozenState[_tokenId];
        if (frozen.isFrozen) {
            revert AlreadyIntendedFrozen();
        }
        frozen.isFrozen = true;
        frozen.timestamp = uint40(block.timestamp);

        emit Freeze(_tokenId);
    }

    /// @inheritdoc IGovNFTTimelock
    function unfreeze(uint256 _tokenId) external nonReentrant {
        _checkAuthorized({owner: _ownerOf(_tokenId), spender: msg.sender, tokenId: _tokenId});

        if (!_frozenState[_tokenId].isFrozen) {
            revert AlreadyIntendedUnfrozen();
        }
        delete _frozenState[_tokenId];

        emit Unfreeze(_tokenId);
    }

    /// @inheritdoc IGovNFT
    function split(
        uint256 _from,
        SplitParams[] calldata _paramsList
    ) external override(GovNFT, IGovNFT) nonReentrant onlyUnfrozen(_from) returns (uint256[] memory) {
        return _split({_from: _from, _paramsList: _paramsList});
    }

    /// @inheritdoc IGovNFT
    function claim(
        uint256 _tokenId,
        address _beneficiary,
        uint256 _amount
    ) external override(GovNFT, IGovNFT) nonReentrant onlyUnfrozen(_tokenId) {
        _claim(_tokenId, _beneficiary, _amount);
    }

    /// @inheritdoc IGovNFT
    function sweep(
        uint256 _tokenId,
        address _token,
        address _recipient
    ) external override(GovNFT, IGovNFT) nonReentrant onlyUnfrozen(_tokenId) {
        _sweep(_tokenId, _token, _recipient, type(uint256).max);
    }

    /// @inheritdoc IGovNFT
    function sweep(
        uint256 _tokenId,
        address _token,
        address _recipient,
        uint256 _amount
    ) external override(GovNFT, IGovNFT) nonReentrant onlyUnfrozen(_tokenId) {
        _sweep(_tokenId, _token, _recipient, _amount);
    }

    /// @dev Override update function to prevent transfers when NFT is frozen, except for minting or burning
    function _update(address _to, uint256 _tokenId, address _auth) internal virtual override returns (address) {
        if (
            (!_frozenState[_tokenId].isFrozen || block.timestamp < _frozenState[_tokenId].timestamp + timelock) &&
            _ownerOf(_tokenId) != address(0) &&
            _to != address(0)
        ) {
            revert UnfrozenToken();
        }

        address from = super._update(_to, _tokenId, _auth);

        // Unfreeze token after transfer
        delete _frozenState[_tokenId];
        return from;
    }
}
