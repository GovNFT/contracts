// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {IArtProxy} from "./interfaces/IArtProxy.sol";
import {IGovNFT} from "./interfaces/IGovNFT.sol";
import {IVault} from "./interfaces/IVault.sol";
import {Vault} from "./Vault.sol";

/// @title GovNFT
/// @notice GovNFT implementation that vests ERC-20 tokens to a given address, in the form of an ERC-721
/// @notice Tokens are vested over a determined period of time, as soon as the cliff period ends
/// @dev    Contract not intended to be used standalone. Should inherit Splitting functionality
///         from one of the available Split modules instead.
abstract contract GovNFT is IGovNFT, ERC721Enumerable, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /// @dev tokenId => Lock state
    mapping(uint256 => Lock) internal _locks;

    /// @dev tokenId => Split child index => Split tokenId
    mapping(uint256 => mapping(uint256 => uint256)) public splitTokensByIndex;

    /// @inheritdoc IGovNFT
    uint256 public tokenId;

    /// @dev ArtProxy address
    address public immutable artProxy;

    /// @dev IGovNFTFactory address
    address public immutable factory;

    /// @inheritdoc IGovNFT
    address public immutable vaultImplementation;

    /// @dev True if lock tokens can be swept before lock expiry
    bool public immutable earlySweepLockToken;

    constructor(
        address _owner,
        address _artProxy,
        address _vaultImplementation,
        string memory _name,
        string memory _symbol,
        bool _earlySweepLockToken
    ) ERC721(_name, _symbol) Ownable(_owner) {
        artProxy = _artProxy;
        factory = msg.sender;
        vaultImplementation = _vaultImplementation;
        earlySweepLockToken = _earlySweepLockToken;
    }

    /// @inheritdoc IGovNFT
    function locks(uint256 _tokenId) external view returns (Lock memory) {
        return _locks[_tokenId];
    }

    /// @inheritdoc IGovNFT
    function unclaimed(uint256 _tokenId) external view returns (uint256) {
        return _unclaimed(_locks[_tokenId]);
    }

    function _unclaimed(Lock storage _lock) internal view returns (uint256) {
        return _totalVested(_lock) + _lock.unclaimedBeforeSplit - _lock.totalClaimed;
    }

    /// @inheritdoc IGovNFT
    function totalVested(uint256 _tokenId) external view returns (uint256) {
        return _totalVested(_locks[_tokenId]);
    }

    function _totalVested(Lock storage _lock) internal view returns (uint256) {
        uint256 time = Math.min(block.timestamp, _lock.end);

        if (time < _lock.start + _lock.cliffLength) {
            return 0;
        }
        return (_lock.totalLocked * (time - _lock.start)) / (_lock.end - _lock.start);
    }

    /// @inheritdoc IGovNFT
    function locked(uint256 _tokenId) external view returns (uint256) {
        return _locked(_locks[_tokenId]);
    }

    function _locked(Lock storage _lock) internal view returns (uint256) {
        return _lock.totalLocked - _totalVested(_lock);
    }

    /// @inheritdoc IGovNFT
    function createLock(
        address _token,
        address _recipient,
        uint256 _amount,
        uint40 _startTime,
        uint40 _endTime,
        uint40 _cliffLength,
        string memory _description
    ) external nonReentrant onlyOwner returns (uint256 _tokenId) {
        if (_token == address(0)) revert ZeroAddress();
        _createLockChecks(_recipient, _amount, _startTime, _endTime, _cliffLength);

        address vault = Clones.clone(vaultImplementation);
        IVault(vault).initialize(_token);
        _tokenId = _createNFT({
            _recipient: _recipient,
            _newLock: Lock({
                totalLocked: _amount,
                initialDeposit: _amount,
                totalClaimed: 0,
                unclaimedBeforeSplit: 0,
                token: _token,
                splitCount: 0,
                cliffLength: _cliffLength,
                start: _startTime,
                end: _endTime,
                vault: vault,
                minter: msg.sender
            })
        });

        IERC20(_token).safeTransferFrom({from: msg.sender, to: vault, value: _amount});
        if (IERC20(_token).balanceOf(vault) < _amount) revert InsufficientAmount();

        emit Create({
            tokenId: _tokenId,
            recipient: _recipient,
            token: _token,
            amount: _amount,
            description: _description
        });
    }

    /// @inheritdoc IGovNFT
    function claim(uint256 _tokenId, address _beneficiary, uint256 _amount) external nonReentrant {
        _checkAuthorized({owner: _ownerOf(_tokenId), spender: msg.sender, tokenId: _tokenId});
        if (_beneficiary == address(0)) revert ZeroAddress();

        Lock storage lock = _locks[_tokenId];
        uint256 claimable = Math.min(_unclaimed(lock), _amount);
        if (claimable == 0) return;

        if (lock.unclaimedBeforeSplit == 0) {
            lock.totalClaimed += claimable;
        } else if (claimable > lock.unclaimedBeforeSplit) {
            lock.totalClaimed += claimable - lock.unclaimedBeforeSplit;
            delete lock.unclaimedBeforeSplit;
        } else {
            lock.unclaimedBeforeSplit -= claimable;
        }

        IVault(lock.vault).withdraw({_recipient: _beneficiary, _amount: claimable});
        emit Claim({tokenId: _tokenId, recipient: _beneficiary, claimed: claimable});
    }

    /// @inheritdoc IGovNFT
    function delegate(uint256 _tokenId, address _delegatee) external nonReentrant {
        _checkAuthorized({owner: _ownerOf(_tokenId), spender: msg.sender, tokenId: _tokenId});

        IVault(_locks[_tokenId].vault).delegate(_delegatee);
        emit Delegate({tokenId: _tokenId, delegate: _delegatee});
    }

    /// @inheritdoc IGovNFT
    function sweep(uint256 _tokenId, address _token, address _recipient) external {
        sweep(_tokenId, _token, _recipient, type(uint256).max);
    }

    /// @inheritdoc IGovNFT
    function sweep(uint256 _tokenId, address _token, address _recipient, uint256 _amount) public nonReentrant {
        if (_token == address(0) || _recipient == address(0)) revert ZeroAddress();
        _checkAuthorized({owner: _ownerOf(_tokenId), spender: msg.sender, tokenId: _tokenId});

        Lock storage lock = _locks[_tokenId];
        address vault = lock.vault;

        if (_token == lock.token) {
            if (!earlySweepLockToken && block.timestamp < lock.end) revert InvalidSweep();
            _amount = Math.min(
                _amount,
                IERC20(_token).balanceOf(vault) - (lock.totalLocked + lock.unclaimedBeforeSplit - lock.totalClaimed)
            );
        } else {
            _amount = Math.min(_amount, IERC20(_token).balanceOf(vault));
        }

        if (_amount == 0) revert ZeroAmount();
        IVault(vault).sweep(_token, _recipient, _amount);
        emit Sweep({tokenId: _tokenId, token: _token, recipient: _recipient, amount: _amount});
    }

    /// @inheritdoc IERC721Metadata
    function tokenURI(uint256 _tokenId) public view override returns (string memory) {
        if (_ownerOf(_tokenId) == address(0)) revert TokenNotFound();
        return IArtProxy(artProxy).tokenURI(_tokenId);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner. Prevents transferring ownership to the factory
     */
    function transferOwnership(address newOwner) public virtual override {
        if (owner() != _msgSender()) revert OwnableUnauthorizedAccount(_msgSender());
        if (newOwner == address(0) || newOwner == factory) {
            revert OwnableInvalidOwner(newOwner);
        }
        _transferOwnership(newOwner);
    }

    /// @dev Creates an NFT designed to vest tokens to the given recipient
    ///      Assumes `_newLock` is a valid lock
    /// @param _recipient Address of the user that will receive funds
    /// @param _newLock Information of the Lock to be created
    /// @return _tokenId The ID of the recently created NFT
    function _createNFT(address _recipient, Lock memory _newLock) internal returns (uint256 _tokenId) {
        unchecked {
            _tokenId = ++tokenId;
        }

        _safeMint({to: _recipient, tokenId: _tokenId});

        _locks[_tokenId] = _newLock;
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
        Lock storage _parentLock,
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
            uint40 parentCliffEnd = _parentLock.start + _parentLock.cliffLength;
            _parentLock.start = uint40(block.timestamp);
            _parentLock.cliffLength = uint40(block.timestamp < parentCliffEnd ? parentCliffEnd - block.timestamp : 0);
        }

        _parentLock.unclaimedBeforeSplit += (_parentTotalVested - _parentLock.totalClaimed);
        delete _parentLock.totalClaimed;
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
        Lock storage _parentLock,
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
            vault: Clones.clone(vaultImplementation),
            minter: msg.sender
        });
        IVault(splitLock.vault).initialize(_parentLock.token);
        _tokenId = _createNFT({_recipient: _params.beneficiary, _newLock: splitLock});

        // Update Parent NFT's Split Token List
        unchecked {
            splitTokensByIndex[_from][_parentLock.splitCount++] = _tokenId;
        }

        // Transfer Split Amount from Parent Vault to new Split Vault
        IVault(_parentLock.vault).withdraw({_recipient: splitLock.vault, _amount: _params.amount});
        if (IERC20(splitLock.token).balanceOf(splitLock.vault) < _params.amount) revert InsufficientAmount();
        emit Split({
            from: _from,
            to: _tokenId,
            recipient: _params.beneficiary,
            splitAmount1: _parentLockedAmount,
            splitAmount2: _params.amount,
            startTime: _params.start,
            endTime: _params.end,
            description: _params.description
        });
    }

    /// @dev Checks if the parameters used to create a Lock are valid
    /// @param _recipient Address to vest tokens for
    /// @param _amount Amount of tokens to be vested for `recipient`
    /// @param _startTime Time at which token distribution starts
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

        if (_endTime == _startTime) revert InvalidParameters();
        if (_endTime - _startTime < _cliff) revert InvalidCliff();
    }

    /// @dev Verifies if the given Split Parameters are valid and consistent with Parent Lock
    /// @param _parentLock Parent NFT's lock information
    /// @param _parentTotalVested Number of tokens vested in Parent Lock
    /// @param _paramsList Array of Parameters to be used to create the new Split NFTs
    function _validateSplitParams(
        Lock storage _parentLock,
        uint256 _parentTotalVested,
        SplitParams[] memory _paramsList
    ) internal view {
        uint256 length = _paramsList.length;
        if (length == 0) revert InvalidParameters();

        uint256 sum;
        SplitParams memory params;
        uint40 parentCliffEnd = _parentLock.start + _parentLock.cliffLength;
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

    /**
     * @dev Throws if owner is not the sender nor the factory.
     * @dev Used in onlyOwner modifier.
     */
    function _checkOwner() internal view override(Ownable) {
        address _owner = owner();
        if (_owner != _msgSender() && _owner != factory) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }
}
