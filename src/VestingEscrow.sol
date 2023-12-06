// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IVestingEscrow} from "./interfaces/IVestingEscrow.sol";

/// @title Velodrome VestingEscrow
/// @author velodrome.finance, @airtoonricardo, @pedrovalido
/// @notice GovNFT implementation that vests ERC-20 tokens to a given address, in the form of an ERC-721
/// @notice Tokens are vested over a determined period of time, as soon as the Cliff period ends
contract VestingEscrow is IVestingEscrow, ReentrancyGuard, ERC721Enumerable {
    using SafeERC20 for IERC20;

    mapping(uint256 => LockedGrant) public grants;
    mapping(uint256 => address) public idToToken;

    mapping(uint256 => address) public idToPendingAdmin;
    mapping(uint256 => address) public idToAdmin;

    mapping(uint256 => uint256) public totalClaimed;
    mapping(uint256 => uint256) public disabledAt;

    constructor() ERC721("GovNFT", "GovNFT") {}

    /// @inheritdoc IVestingEscrow
    function unclaimed(uint256 _tokenId) external view returns (uint256) {
        return _unclaimed(_tokenId, Math.min(block.timestamp, disabledAt[_tokenId]));
    }

    function _unclaimed(uint256 _tokenId, uint256 time) internal view returns (uint256) {
        return _totalVestedAt(_tokenId, time) - totalClaimed[_tokenId];
    }

    function _totalVestedAt(uint256 _tokenId, uint256 _time) internal view returns (uint256) {
        LockedGrant memory grant = grants[_tokenId];
        if (_time < grant.start + grant.cliffLength) {
            return 0;
        }
        return Math.min((grant.totalLocked * (_time - grant.start)) / (grant.end - grant.start), grant.totalLocked);
    }

    /// @inheritdoc IVestingEscrow
    function locked(uint256 _tokenId) external view returns (uint256) {
        return _locked(_tokenId, Math.min(block.timestamp, disabledAt[_tokenId]));
    }

    function _locked(uint256 _tokenId, uint256 time) internal view returns (uint256) {
        return grants[_tokenId].totalLocked - _totalVestedAt(_tokenId, time);
    }

    /// @inheritdoc IVestingEscrow
    function createGrant(
        address _token,
        address _recipient,
        uint256 _amount,
        uint256 _duration,
        uint256 _cliffLength
    ) external nonReentrant returns (uint256) {
        return _createGrant(_token, _recipient, _amount, block.timestamp, block.timestamp + _duration, _cliffLength);
    }

    /// @inheritdoc IVestingEscrow
    function createGrant(
        address _token,
        address _recipient,
        uint256 _amount,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _cliffLength
    ) external nonReentrant returns (uint256) {
        if (_startTime < block.timestamp) revert VestingStartTooOld();
        return _createGrant(_token, _recipient, _amount, _startTime, _endTime, _cliffLength);
    }

    function _createGrant(
        address _token,
        address _recipient,
        uint256 _amount,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _cliffLength
    ) internal returns (uint256) {
        if (_token == address(0) || _recipient == address(0)) revert ZeroAddress();
        if (_amount == 0) revert ZeroAmount();
        if (_startTime >= _endTime) revert EndBeforeOrEqual();
        if (_endTime - _startTime < _cliffLength) revert InvalidCliff();

        uint256 _tokenId = totalSupply() + 1;
        idToAdmin[_tokenId] = msg.sender;
        idToToken[_tokenId] = _token;

        _mint(_recipient, _tokenId);

        grants[_tokenId] = LockedGrant(_amount, _cliffLength, _startTime, _endTime);
        disabledAt[_tokenId] = _endTime;

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        emit Fund(_tokenId, _recipient, _token, _amount);
        return _tokenId;
    }

    /// @inheritdoc IVestingEscrow
    function claim(uint256 _tokenId, address beneficiary, uint256 amount) external nonReentrant {
        _claim(_tokenId, beneficiary, amount);
    }

    /// @inheritdoc IVestingEscrow
    function claim(uint256 _tokenId, address beneficiary) external nonReentrant {
        _claim(_tokenId, beneficiary, type(uint256).max);
    }

    function _claim(uint256 _tokenId, address beneficiary, uint256 amount) internal {
        _checkAuthorized(_ownerOf(_tokenId), msg.sender, _tokenId);
        if (beneficiary == address(0)) revert ZeroAddress();

        uint256 _claimPeriodEnd = Math.min(block.timestamp, disabledAt[_tokenId]);
        uint256 _claimable = Math.min(_unclaimed(_tokenId, _claimPeriodEnd), amount);
        totalClaimed[_tokenId] += _claimable;

        IERC20(idToToken[_tokenId]).safeTransfer(beneficiary, _claimable);
        emit Claim(_tokenId, beneficiary, _claimable);
    }

    /// @inheritdoc IVestingEscrow
    function setAdmin(uint256 _tokenId, address addr) external {
        if (msg.sender != idToAdmin[_tokenId]) revert NotAdmin();
        if (addr == address(0)) revert ZeroAddress();
        idToPendingAdmin[_tokenId] = addr;
        emit SetAdmin(_tokenId, addr);
    }

    /// @inheritdoc IVestingEscrow
    function acceptAdmin(uint256 _tokenId) external {
        if (msg.sender != idToPendingAdmin[_tokenId]) revert NotPendingAdmin();
        idToAdmin[_tokenId] = msg.sender;
        idToPendingAdmin[_tokenId] = address(0);
        emit AcceptAdmin(_tokenId, msg.sender);
    }

    /// @inheritdoc IVestingEscrow
    function renounceAdmin(uint256 _tokenId) external {
        if (msg.sender != idToAdmin[_tokenId]) revert NotAdmin();
        idToPendingAdmin[_tokenId] = address(0);
        idToAdmin[_tokenId] = address(0);
        emit AcceptAdmin(_tokenId, address(0));
    }

    /// @inheritdoc IVestingEscrow
    function rugPull(uint256 _tokenId) external nonReentrant {
        address _admin = idToAdmin[_tokenId];
        if (msg.sender != _admin) revert NotAdmin();
        if (disabledAt[_tokenId] <= block.timestamp) revert AlreadyDisabled();
        // NOTE: Rugging more than once is futile

        disabledAt[_tokenId] = block.timestamp;
        uint256 ruggable = _locked(_tokenId, block.timestamp);

        IERC20(idToToken[_tokenId]).safeTransfer(_admin, ruggable);
        emit RugPull(_tokenId, _ownerOf(_tokenId), ruggable);
    }
}
