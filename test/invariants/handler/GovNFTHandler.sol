// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import "forge-std/Test.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {TestOwner} from "test/utils/TestOwner.sol";
import {TimeStore} from "test/invariants/TimeStore.sol";
import {GovNFTInvariants} from "test/invariants/GovNFTInvariants.sol";

import {GovNFTSplit} from "src/extensions/GovNFTSplit.sol";
import {IGovNFT} from "src/interfaces/IGovNFT.sol";

abstract contract GovNFTHandler is Test {
    using EnumerableSet for EnumerableSet.AddressSet;

    GovNFTSplit public govNFT;
    TimeStore public timestore;
    GovNFTInvariants public testContract;

    address public testToken;
    address public airdropToken;

    TestOwner[] public actors;
    TestOwner internal currentActor;
    EnumerableSet.AddressSet internal actorsWithLocks;

    uint256 public totalDeposited;
    uint256 constant MAX_SPLITS = 2;
    uint256 constant TOKEN_100K = 1e23; // 1e5 = 100K tokens with 18 decimals
    uint256 public immutable maxLockCount;

    // @dev Keeps track of all tokens claimed for a Lock, regardless if it has been split
    mapping(uint256 tokenId => uint256 totalClaimed) public idToPersistentClaims;

    constructor(
        GovNFTSplit _govNFT,
        TimeStore _timestore,
        address _testToken,
        address _airdropToken,
        uint256 _testActorCount,
        uint256 _initialDeposit,
        uint256 _maxLocks
    ) {
        govNFT = _govNFT;
        testToken = _testToken;
        timestore = _timestore;
        maxLockCount = _maxLocks;
        airdropToken = _airdropToken;
        totalDeposited = _initialDeposit;
        actors = new TestOwner[](_testActorCount);
        testContract = GovNFTInvariants(msg.sender);
        for (uint256 i = 0; i < _testActorCount; i++) {
            actors[i] = new TestOwner();
        }
        _setUpHandler();
    }

    function _setUpHandler() internal virtual;

    function _generateSplitTimestamps(
        uint256 _tokenId,
        uint256 _salt
    ) internal view virtual returns (uint40 start, uint40 end, uint40 cliff);

    function _getRandomActor(uint256 _actorSeed) internal view returns (address) {
        return address(actors[bound(_actorSeed, 0, actors.length - 1)]);
    }

    function _getRandomLockOfCurrentActor(uint256 _tokenIdSeed) internal view returns (uint256) {
        address actor = address(currentActor);
        return govNFT.tokenOfOwnerByIndex({owner: actor, index: bound(_tokenIdSeed, 0, govNFT.balanceOf(actor) - 1)});
    }

    modifier useActor(uint256 _actorIndex) {
        currentActor = actors[bound(_actorIndex, 0, actors.length - 1)];
        vm.startPrank(address(currentActor));
        _;
        vm.stopPrank();
    }

    modifier useActorWithLocks(uint256 _actorIndex) {
        // Only execute if there is an Actor with Locks
        if (actorsWithLocks.length() > 0) {
            currentActor = TestOwner(actorsWithLocks.at(bound(_actorIndex, 0, actorsWithLocks.length() - 1)));
            vm.startPrank(address(currentActor));
            _;
            vm.stopPrank();
        }
    }

    modifier increaseTimestamp(uint256 _timeskipSeed) {
        timestore.increaseCurrentTimestamp({timeskip: bound(_timeskipSeed, 0, 4 weeks)});
        vm.warp(timestore.currentTimestamp());
        vm.roll(timestore.currentBlockNumber());
        _;
    }

    /// @dev If `maxLockCount` is exceeded, test Sweep or Claim instead
    modifier maxLocks(
        uint256 _amount,
        uint256 _actorIndex,
        uint256 _salt
    ) {
        if (govNFT.tokenId() >= maxLockCount) {
            if (_amount % 2 == 0) {
                claim({
                    _tokenId: uint256((keccak256(abi.encode(_amount, _salt)))),
                    _amount: _amount,
                    _actorIndex: _actorIndex,
                    _beneficiaryActorIndex: uint256((keccak256(abi.encode(_actorIndex, _salt)))),
                    // @dev 0 Timeskip because time is already skipped in `increaseTimestamp`
                    _timeskipSeed: 0
                });
            } else {
                sweep({
                    _tokenId: uint256((keccak256(abi.encode(_amount, _salt)))),
                    _amount: _amount,
                    _actorIndex: _actorIndex,
                    _beneficiaryActorIndex: uint256((keccak256(abi.encode(_actorIndex, _salt)))),
                    // @dev 0 Timeskip because time is already skipped in `increaseTimestamp`
                    _timeskipSeed: 0
                });
            }
        } else {
            // Only create more locks if Max is not exceeded
            _;
        }
    }

    function createLock(
        uint256 _amount,
        uint40 _startTime,
        uint40 _endTime,
        uint40 _cliffLength,
        uint256 _actorIndex,
        uint256 _timeskipSeed
    ) external useActor(_actorIndex) increaseTimestamp(_timeskipSeed) maxLocks(_amount, _actorIndex, _timeskipSeed) {
        _startTime = uint40(
            bound(_startTime, block.timestamp, Math.min(block.timestamp + 4 weeks, type(uint40).max - 6 weeks - 1))
        );
        _endTime = uint40(bound(_endTime, _startTime + 1, _startTime + 6 weeks));
        _cliffLength = uint40(bound(_cliffLength, 0, _endTime - _startTime));

        _amount = bound(_amount, TOKEN_100K / 2, TOKEN_100K);
        deal(testToken, address(currentActor), _amount);
        currentActor.approve(testToken, address(govNFT), _amount);

        govNFT.createLock({
            _token: testToken, // creating locks in test token by default
            _recipient: address(currentActor),
            _amount: _amount,
            _startTime: _startTime,
            _endTime: _endTime,
            _cliffLength: _cliffLength,
            _description: ""
        });
        actorsWithLocks.add(address(currentActor));
        totalDeposited += _amount;
    }

    function claim(
        uint256 _tokenId,
        uint256 _amount,
        uint256 _actorIndex,
        uint256 _beneficiaryActorIndex,
        uint256 _timeskipSeed
    ) public useActorWithLocks(_actorIndex) increaseTimestamp(_timeskipSeed) {
        // Select a Random actor to be the Recipient
        address beneficiary = _getRandomActor({_actorSeed: _beneficiaryActorIndex});

        _tokenId = _getRandomLockOfCurrentActor({_tokenIdSeed: _tokenId});

        _amount = bound(_amount, 0, govNFT.unclaimed(_tokenId));

        idToPersistentClaims[_tokenId] += _amount;
        govNFT.claim({_tokenId: _tokenId, _beneficiary: beneficiary, _amount: _amount});
    }

    function sweep(
        uint256 _tokenId,
        uint256 _amount,
        uint256 _actorIndex,
        uint256 _beneficiaryActorIndex,
        uint256 _timeskipSeed
    ) public useActorWithLocks(_actorIndex) increaseTimestamp(_timeskipSeed) {
        // Select a Random actor to be the Recipient
        address beneficiary = _getRandomActor({_actorSeed: _beneficiaryActorIndex});

        _tokenId = _getRandomLockOfCurrentActor({_tokenIdSeed: _tokenId});

        // Only sweep Lock token if Lock has finished vesting
        address token = govNFT.locks(_tokenId).end >= block.timestamp ? airdropToken : testToken;
        address vault = govNFT.locks(_tokenId).vault;
        _amount = bound(_amount, 1, 10 * TOKEN_100K);

        deal(token, vault, IERC20(token).balanceOf(vault) + _amount);
        govNFT.sweep({_tokenId: _tokenId, _token: token, _recipient: beneficiary, _amount: _amount});
    }

    function split(
        uint256 _tokenId,
        uint256 _amount,
        uint256 _actorIndex,
        uint256 _beneficiaryActorIndex,
        uint256 _timeskipSeed,
        uint8 _splitCount
    )
        external
        useActorWithLocks(_actorIndex)
        increaseTimestamp(_timeskipSeed)
        maxLocks(_amount, _actorIndex, _timeskipSeed)
    {
        if (govNFT.tokenId() > 5) return;
        _tokenId = _getRandomLockOfCurrentActor({_tokenIdSeed: _tokenId});

        // Split Lock in `_splitCount` childLocks
        uint40 parentEnd = govNFT.locks(_tokenId).end;
        uint256 totalSplitAmount = Math.min(govNFT.locked(_tokenId), TOKEN_100K);
        if (totalSplitAmount > 1 && parentEnd > block.timestamp) {
            // Ensure `totalSplitAmount` can be divided by `_splitCount`
            _splitCount = uint8(bound(_splitCount, 2, Math.min(totalSplitAmount, MAX_SPLITS)));

            IGovNFT.SplitParams[] memory params = new IGovNFT.SplitParams[](_splitCount);
            for (uint256 i = 0; i < _splitCount; i++) {
                // Select a Random actor to be the Recipient
                params[i].beneficiary = _getRandomActor({
                    _actorSeed: uint256((keccak256(abi.encode(_beneficiaryActorIndex, i))))
                });
                actorsWithLocks.add(params[i].beneficiary);

                // Generate random Split Amount
                params[i].amount = bound({
                    x: uint256(keccak256(abi.encode(_amount, i))),
                    min: 1,
                    max: totalSplitAmount / _splitCount
                });

                // Generate random Timestamp parameters for Child Lock
                (params[i].start, params[i].end, params[i].cliff) = _generateSplitTimestamps({
                    _tokenId: _tokenId,
                    _salt: i
                });
            }
            govNFT.split({_from: _tokenId, _paramsList: params});
        }
    }
}
