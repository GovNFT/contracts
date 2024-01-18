// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IVestingEscrow} from "./interfaces/IVestingEscrow.sol";
import {IVault} from "./interfaces/IVault.sol";
import {Vault} from "./Vault.sol";

/// @title Velodrome VestingEscrow
/// @author velodrome.finance, @airtoonricardo, @pedrovalido
/// @notice GovNFT implementation that vests ERC-20 tokens to a given address, in the form of an ERC-721
/// @notice Tokens are vested over a determined period of time, as soon as the Cliff period ends
contract VestingEscrow is IVestingEscrow, ReentrancyGuard, ERC721Enumerable {
    using SafeERC20 for IERC20;

    mapping(uint256 => LockedGrant) public grants;

    mapping(uint256 => mapping(uint256 => uint256)) public splitTokensByIndex;

    constructor() ERC721("GovNFT", "GovNFT") {}

    /// @inheritdoc IVestingEscrow
    function unclaimed(uint256 _tokenId) external view returns (uint256) {
        return _unclaimed(_tokenId);
    }

    function _unclaimed(uint256 _tokenId) internal view returns (uint256) {
        return _totalVested(_tokenId) + grants[_tokenId].unclaimedBeforeSplit - grants[_tokenId].totalClaimed;
    }

    function _totalVested(uint256 _tokenId) internal view returns (uint256) {
        LockedGrant memory grant = grants[_tokenId];
        uint256 time = Math.min(block.timestamp, grant.end);

        if (time < grant.start + grant.cliffLength) {
            return 0;
        }
        return (grant.totalLocked * (time - grant.start)) / (grant.end - grant.start);
    }

    /// @inheritdoc IVestingEscrow
    function locked(uint256 _tokenId) external view returns (uint256) {
        return _locked(_tokenId);
    }

    function _locked(uint256 _tokenId) internal view returns (uint256) {
        return grants[_tokenId].totalLocked - _totalVested(_tokenId);
    }

    /// @inheritdoc IVestingEscrow
    function createGrant(
        address _token,
        address _recipient,
        uint256 _amount,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _cliffLength
    ) external nonReentrant returns (uint256 _tokenId) {
        if (_startTime < block.timestamp) revert VestingStartTooOld();

        if (_token == address(0) || _recipient == address(0)) revert ZeroAddress();
        if (_amount == 0) revert ZeroAmount();
        if (_startTime >= _endTime) revert EndBeforeOrEqualStart();
        if (_endTime - _startTime < _cliffLength) revert InvalidCliff();

        address _vault = address(new Vault(_token));
        _tokenId = _createNFT(
            _recipient,
            LockedGrant(_amount, _amount, 0, 0, 0, _cliffLength, _startTime, _endTime, _token, _vault, msg.sender)
        );

        IERC20(_token).safeTransferFrom(msg.sender, _vault, _amount);

        emit Fund(_tokenId, _recipient, _token, _amount);
    }

    /// @inheritdoc IVestingEscrow
    function claim(uint256 _tokenId, address _beneficiary, uint256 _amount) external nonReentrant {
        _checkAuthorized(_ownerOf(_tokenId), msg.sender, _tokenId);
        if (_beneficiary == address(0)) revert ZeroAddress();

        uint256 _claimable = Math.min(_unclaimed(_tokenId), _amount);

        LockedGrant memory grant = grants[_tokenId];
        if (_claimable >= grant.unclaimedBeforeSplit) {
            grant.totalClaimed += _claimable - grant.unclaimedBeforeSplit;
            delete grant.unclaimedBeforeSplit;
        } else {
            grant.unclaimedBeforeSplit -= _claimable;
        }

        IVault(grant.vault).withdraw(_beneficiary, _claimable);
        grants[_tokenId] = grant;
        emit Claim(_tokenId, _beneficiary, _claimable);
    }

    /// @inheritdoc IVestingEscrow
    function split(
        address _beneficiary,
        uint256 _from,
        uint256 _amount,
        uint256 _start,
        uint256 _end,
        uint256 _cliff
    ) external nonReentrant returns (uint256 _tokenId) {
        _checkAuthorized(_ownerOf(_from), msg.sender, _from);

        if (_amount == 0) revert ZeroAmount();
        if (_beneficiary == address(0)) revert ZeroAddress();

        LockedGrant memory newGrant = grants[_from];
        uint256 _endOfCliff = newGrant.start + newGrant.cliffLength;

        if (_end < newGrant.end) revert InvalidEnd();
        if (_start < newGrant.start || _start < block.timestamp) revert VestingStartTooOld();
        if (_start + _cliff < _endOfCliff || _end - _start < _cliff) revert InvalidCliff();

        // Update Original NFT
        uint256 _newLock = _updateGrantAfterSplit(_from, _amount, _endOfCliff, newGrant);

        (newGrant.cliffLength, newGrant.start, newGrant.end) = (_cliff, _start, _end);

        // Create Split NFT using _amount
        newGrant.totalLocked = _amount;
        newGrant.initialDeposit = _amount;
        delete newGrant.unclaimedBeforeSplit;
        address parentVault = newGrant.vault;
        newGrant.vault = address(new Vault(newGrant.token));
        _tokenId = _createNFT(_beneficiary, newGrant);

        _addTokenToSplitList(_from, _tokenId);
        IVault(parentVault).withdraw(newGrant.vault, _amount);
        emit Split(_from, _tokenId, _beneficiary, _newLock, _amount, newGrant.start, newGrant.end);
    }

    /// @inheritdoc IVestingEscrow
    function delegate(uint256 _tokenId, address delegatee) external {
        _checkAuthorized(_ownerOf(_tokenId), msg.sender, _tokenId);
        if (delegatee == address(0)) revert ZeroAddress();

        IVault(grants[_tokenId].vault).delegate(delegatee);
        emit Delegate(_tokenId, delegatee);
    }

    /// @dev Creates an NFT designed to vest tokens to the given recipient
    ///      Assumes `_newGrant` is a valid grant
    /// @param _recipient Address of the user that will receive funds
    /// @param _newGrant Information of the Grant to be created
    /// @return _tokenId The ID of the recently created NFT
    function _createNFT(address _recipient, LockedGrant memory _newGrant) private returns (uint256 _tokenId) {
        _tokenId = totalSupply() + 1;

        _mint(_recipient, _tokenId);

        grants[_tokenId] = _newGrant;
    }

    /// @dev Updates the current Locked Grant information of a Parent NFT after splitting it
    ///      After execution, the value of the `grant` variable will be updated
    ///      Throws if `_amount` is greater than the Parent NFT's locked balance
    /// @param _from ID of the parent NFT to be updated
    /// @param _amount Amount to be split from Parent NFT's locked balance
    /// @param _endOfCliff End of the Parent NFT's cliff
    /// @param grant Parent NFT's Locked Grant information to be updated
    /// @return newLock The value of the new Lock for the Parent NFT
    function _updateGrantAfterSplit(
        uint256 _from,
        uint256 _amount,
        uint256 _endOfCliff,
        LockedGrant memory grant
    ) private returns (uint256 newLock) {
        uint256 totalVested = _totalVested(_from);
        uint256 _locked_ = grant.totalLocked - totalVested;
        if (_locked_ <= _amount) revert AmountTooBig();

        newLock = _locked_ - _amount;

        grant.totalLocked = newLock;
        if (block.timestamp > grant.start) {
            grant.start = block.timestamp;
            grant.cliffLength = block.timestamp < _endOfCliff ? _endOfCliff - block.timestamp : 0;
        }

        // Update NFT using _locked_ - _amount
        grant.unclaimedBeforeSplit += totalVested - grant.totalClaimed;
        delete grant.totalClaimed;
        grants[_from] = grant;
    }

    /// @dev Add a Split NFT to the Split index mapping of its parent NFT
    /// @param _from ID of the Parent NFT
    /// @param _tokenId ID of the new Split NFT
    function _addTokenToSplitList(uint256 _from, uint256 _tokenId) private {
        uint256 length = grants[_from].splitCount;
        splitTokensByIndex[_from][length] = _tokenId;
        grants[_from].splitCount = length + 1;
    }

    /// @inheritdoc IVestingEscrow
    function sweep(uint256 _tokenId, address _token, address _recipient) external {
        sweep(_tokenId, _token, _recipient, type(uint256).max);
    }

    /// @inheritdoc IVestingEscrow
    function sweep(uint256 _tokenId, address _token, address _recipient, uint256 amount) public nonReentrant {
        if (_token == address(0) || _recipient == address(0)) revert ZeroAddress();
        _checkAuthorized(_ownerOf(_tokenId), msg.sender, _tokenId);

        LockedGrant memory grant = grants[_tokenId];
        address vault = grant.vault;

        if (_token == grant.token) {
            amount = Math.min(amount, IERC20(_token).balanceOf(vault) - (grant.totalLocked - grant.totalClaimed));
        } else {
            amount = Math.min(amount, IERC20(_token).balanceOf(vault));
        }
        if (amount == 0) revert ZeroAmount();

        IVault(vault).sweep(_token, _recipient, amount);
        emit Sweep(_tokenId, _token, _recipient, amount);
    }
}
