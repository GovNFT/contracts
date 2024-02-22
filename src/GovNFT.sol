// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IGovNFT} from "./interfaces/IGovNFT.sol";
import {IVault} from "./interfaces/IVault.sol";
import {Vault} from "./Vault.sol";

/// @title Velodrome GovNFT
/// @author velodrome.finance, @airtoonricardo, @pedrovalido
/// @notice GovNFT implementation that vests ERC-20 tokens to a given address, in the form of an ERC-721
/// @notice Tokens are vested over a determined period of time, as soon as the Cliff period ends
/// @dev    Contract not intended to be used standalone. Should inherit Splitting functionality
///         from one of the available Split modules instead.
abstract contract GovNFT is IGovNFT, ReentrancyGuard, ERC721Enumerable {
    using SafeERC20 for IERC20;

    /// @dev tokenId => Lock state
    mapping(uint256 => Lock) public locks;

    /// @dev tokenId => Split child index => Split tokenId
    mapping(uint256 => mapping(uint256 => uint256)) public splitTokensByIndex;

    /// @inheritdoc IGovNFT
    uint256 public tokenId;

    constructor() ERC721("GovNFT", "GovNFT") {}

    /// @inheritdoc IGovNFT
    function unclaimed(uint256 _tokenId) external view returns (uint256) {
        return _unclaimed(_tokenId);
    }

    function _unclaimed(uint256 _tokenId) internal view returns (uint256) {
        return _totalVested(_tokenId) + locks[_tokenId].unclaimedBeforeSplit - locks[_tokenId].totalClaimed;
    }

    function _totalVested(uint256 _tokenId) internal view returns (uint256) {
        Lock memory lock = locks[_tokenId];
        uint256 time = Math.min(block.timestamp, lock.end);

        if (time < lock.start + lock.cliffLength) {
            return 0;
        }
        return (lock.totalLocked * (time - lock.start)) / (lock.end - lock.start);
    }

    /// @inheritdoc IGovNFT
    function locked(uint256 _tokenId) external view returns (uint256) {
        return _locked(_tokenId);
    }

    function _locked(uint256 _tokenId) internal view returns (uint256) {
        return locks[_tokenId].totalLocked - _totalVested(_tokenId);
    }

    /// @inheritdoc IGovNFT
    function createLock(
        address _token,
        address _recipient,
        uint256 _amount,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _cliffLength
    ) external nonReentrant returns (uint256 _tokenId) {
        if (_token == address(0)) revert ZeroAddress();
        _createLockChecks(_recipient, _amount, _startTime, _endTime, _cliffLength);

        address _vault = address(new Vault(_token));
        _tokenId = _createNFT(
            _recipient,
            Lock(_amount, _amount, 0, 0, 0, _cliffLength, _startTime, _endTime, _token, _vault, msg.sender)
        );

        IERC20(_token).safeTransferFrom(msg.sender, _vault, _amount);
        if (IERC20(_token).balanceOf(_vault) < _amount) revert InsufficientAmount();

        emit Create(_tokenId, _recipient, _token, _amount);
    }

    /// @inheritdoc IGovNFT
    function claim(uint256 _tokenId, address _beneficiary, uint256 _amount) external nonReentrant {
        _checkAuthorized(_ownerOf(_tokenId), msg.sender, _tokenId);
        if (_beneficiary == address(0)) revert ZeroAddress();

        uint256 _claimable = Math.min(_unclaimed(_tokenId), _amount);

        Lock memory lock = locks[_tokenId];
        if (_claimable > lock.unclaimedBeforeSplit) {
            lock.totalClaimed += _claimable - lock.unclaimedBeforeSplit;
            delete lock.unclaimedBeforeSplit;
        } else {
            lock.unclaimedBeforeSplit -= _claimable;
        }

        locks[_tokenId] = lock;
        IVault(lock.vault).withdraw(_beneficiary, _claimable);
        emit Claim(_tokenId, _beneficiary, _claimable);
    }

    /// @inheritdoc IGovNFT
    function delegate(uint256 _tokenId, address delegatee) external nonReentrant {
        _checkAuthorized(_ownerOf(_tokenId), msg.sender, _tokenId);

        IVault(locks[_tokenId].vault).delegate(delegatee);
        emit Delegate(_tokenId, delegatee);
    }

    /// @dev Creates an NFT designed to vest tokens to the given recipient
    ///      Assumes `_newLock` is a valid lock
    /// @param _recipient Address of the user that will receive funds
    /// @param _newLock Information of the Lock to be created
    /// @return _tokenId The ID of the recently created NFT
    function _createNFT(address _recipient, Lock memory _newLock) internal returns (uint256 _tokenId) {
        _tokenId = ++tokenId;

        _safeMint(_recipient, _tokenId);

        locks[_tokenId] = _newLock;
    }

    /// @dev Creates Split NFTs from the given Parent NFT
    ///      Assumes that the given Split Parameters are valid
    /// @param _from Token ID of the Parent NFT to be split
    /// @param _parentTotalVested Number of tokens vested in Parent Lock
    /// @param _parentLock Parent NFT's lock information
    /// @param _paramsList Array of Parameters to be used to create the new Split NFTs
    /// @return _splitTokenIds Returns the token IDs of the new Split NFTs
    function _split(
        uint256 _from,
        uint256 _parentTotalVested,
        Lock memory _parentLock,
        SplitParams[] memory _paramsList
    ) internal returns (uint256[] memory _splitTokenIds) {
        SplitParams memory params;
        uint256 length = _paramsList.length;
        _splitTokenIds = new uint256[](length);
        uint256 parentLockedAmount = _parentLock.totalLocked - _parentTotalVested;
        for (uint256 i = 0; i < length; i++) {
            params = _paramsList[i];
            parentLockedAmount -= params.amount;

            // @dev This call implicitly updates `_parentLock.splitCount`
            _splitTokenIds[i] = _createSplitNFT({
                _from: _from,
                _parentLockedAmount: parentLockedAmount,
                _parentLock: _parentLock,
                _params: params
            });
        }
        // Update Parent NFT using updated `parentLockedAmount`
        _parentLock.totalLocked = parentLockedAmount;
        if (block.timestamp > _parentLock.start) {
            uint256 parentCliffEnd = _parentLock.start + _parentLock.cliffLength;
            _parentLock.start = block.timestamp;
            _parentLock.cliffLength = block.timestamp < parentCliffEnd ? parentCliffEnd - block.timestamp : 0;
        }

        _parentLock.unclaimedBeforeSplit += (_parentTotalVested - _parentLock.totalClaimed);
        delete _parentLock.totalClaimed;
        locks[_from] = _parentLock;
        emit MetadataUpdate(_from);
    }

    /// @dev Creates a new Split NFT from the given Parent NFT
    ///      Assumes that the given Split Parameters are valid
    /// @param _from Token ID of the Parent NFT to be split
    /// @param _parentLockedAmount Amount of tokens still locked in Parent Lock
    /// @param _parentLock Parent NFT's lock information
    /// @param _params Parameters to be used to create the new Split NFT
    /// @return _tokenId Returns the token ID of the new Split NFT
    function _createSplitNFT(
        uint256 _from,
        uint256 _parentLockedAmount,
        Lock memory _parentLock,
        SplitParams memory _params
    ) internal virtual returns (uint256 _tokenId) {
        // Create Split NFT using params.amount
        Lock memory splitLock = Lock({
            totalLocked: _params.amount,
            initialDeposit: _params.amount,
            totalClaimed: 0,
            unclaimedBeforeSplit: 0,
            splitCount: 0,
            cliffLength: _params.cliff,
            start: _params.start,
            end: _params.end,
            token: _parentLock.token,
            vault: address(new Vault(_parentLock.token)),
            minter: msg.sender
        });
        _tokenId = _createNFT({_recipient: _params.beneficiary, _newLock: splitLock});

        // Update Parent NFT's Split Token List
        splitTokensByIndex[_from][_parentLock.splitCount++] = _tokenId;

        // Transfer Split Amount from Parent Vault to new Split Vault
        IVault(_parentLock.vault).withdraw({_receiver: splitLock.vault, _amount: _params.amount});
        if (IERC20(splitLock.token).balanceOf(splitLock.vault) < _params.amount) revert InsufficientAmount();
        emit Split({
            from: _from,
            tokenId: _tokenId,
            recipient: _params.beneficiary,
            splitAmount1: _parentLockedAmount,
            splitAmount2: _params.amount,
            startTime: _params.start,
            endTime: _params.end
        });
    }

    /// @dev Verifies if the given Split Parameters are valid and consistent with Parent Lock
    /// @param _parentLock Parent NFT's lock information
    /// @param _parentTotalVested Number of tokens vested in Parent Lock
    /// @param _paramsList Array of Parameters to be used to create the new Split NFTs
    function _validateSplitParams(
        Lock memory _parentLock,
        uint256 _parentTotalVested,
        SplitParams[] memory _paramsList
    ) internal view {
        uint256 length = _paramsList.length;
        if (length == 0) revert InvalidParameters();

        uint256 sum;
        SplitParams memory params;
        uint256 parentCliffEnd = _parentLock.start + _parentLock.cliffLength;
        for (uint256 i = 0; i < length; i++) {
            params = _paramsList[i];

            // Ensure Split parameters are valid
            _createLockChecks({
                _recipient: params.beneficiary,
                _amount: params.amount,
                _startTime: params.start,
                _endTime: params.end,
                _cliff: params.cliff
            });

            if (params.end < _parentLock.end) revert InvalidEnd();
            if (params.start < _parentLock.start) revert InvalidStart();
            if (params.start + params.cliff < parentCliffEnd) revert InvalidCliff();

            sum += params.amount;
        }

        if (_parentLock.totalLocked - _parentTotalVested < sum) revert AmountTooBig();
    }

    /// @dev Checks if the parameters used to create a Lock are valid
    /// @param _recipient Address to vest tokens for
    /// @param _amount Amount of tokens to be vested for `recipient`
    /// @param _startTime Epoch time at which token distribution starts
    /// @param _endTime Time at which everything should be vested
    /// @param _cliff Duration after which the first portion vests
    function _createLockChecks(
        address _recipient,
        uint256 _amount,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _cliff
    ) internal view {
        if (_startTime < block.timestamp) revert InvalidStart();
        if (_recipient == address(0)) revert ZeroAddress();
        if (_amount == 0) revert ZeroAmount();

        if (_startTime >= _endTime) revert EndBeforeOrEqualStart();
        if (_endTime - _startTime < _cliff) revert InvalidCliff();
    }

    /// @inheritdoc IGovNFT
    function sweep(uint256 _tokenId, address _token, address _recipient) external {
        sweep(_tokenId, _token, _recipient, type(uint256).max);
    }

    /// @inheritdoc IGovNFT
    function sweep(uint256 _tokenId, address _token, address _recipient, uint256 amount) public nonReentrant {
        if (_token == address(0) || _recipient == address(0)) revert ZeroAddress();
        _checkAuthorized(_ownerOf(_tokenId), msg.sender, _tokenId);

        Lock memory lock = locks[_tokenId];
        address vault = lock.vault;

        if (_token == lock.token) {
            amount = Math.min(amount, IERC20(_token).balanceOf(vault) - (lock.totalLocked - lock.totalClaimed));
        } else {
            amount = Math.min(amount, IERC20(_token).balanceOf(vault));
        }
        if (amount == 0) revert ZeroAmount();

        IVault(vault).sweep(_token, _recipient, amount);
        emit Sweep(_tokenId, _token, _recipient, amount);
    }
}
