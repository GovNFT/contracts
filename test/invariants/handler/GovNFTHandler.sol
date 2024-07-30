// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "forge-std/Test.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {TestOwner} from "test/utils/TestOwner.sol";
import {TimeStore} from "test/invariants/TimeStore.sol";
import {GovNFTInvariants} from "test/invariants/GovNFTInvariants.sol";

import {GovNFT} from "src/GovNFT.sol";
import {IGovNFT} from "src/interfaces/IGovNFT.sol";

abstract contract GovNFTHandler is Test {
    using EnumerableSet for EnumerableSet.AddressSet;

    GovNFT public govNFT;
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

    // @dev Keeps track of all tokens claimed for a Lock, regardless if it has been split
    mapping(uint256 tokenId => uint256 totalClaimed) public idToPersistentClaims;

    constructor(
        GovNFT _govNFT,
        TimeStore _timestore,
        address _testToken,
        address _airdropToken,
        uint256 _testActorCount,
        uint256 _initialDeposit
    ) {
        govNFT = _govNFT;
        testToken = _testToken;
        timestore = _timestore;
        airdropToken = _airdropToken;
        totalDeposited = _initialDeposit;
        actors = new TestOwner[](_testActorCount);
        testContract = GovNFTInvariants(msg.sender);
        for (uint256 i = 0; i < _testActorCount; i++) {
            actors[i] = new TestOwner();
        }
        timestore.increaseCurrentTimestamp({timeskip: 3 weeks});
        vm.warp(timestore.currentTimestamp());
        vm.roll(timestore.currentBlockNumber());
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

    function createLock(
        uint256 _amount,
        uint40 _startTime,
        uint40 _endTime,
        uint40 _cliffLength,
        uint256 _actorIndex,
        uint256 _timeskipSeed
    ) external useActor(_actorIndex) increaseTimestamp(_timeskipSeed) {
        _startTime = uint40(
            bound(
                _startTime,
                block.timestamp - 2 weeks,
                Math.min(block.timestamp + 4 weeks, type(uint40).max - 6 weeks - 1)
            )
        );
        /// @dev `_endTime` should be invalid if smaller or equal to `_startTime`
        _endTime = uint40(bound(_endTime, _startTime - 1 weeks, _startTime + 6 weeks));
        /// @dev `_cliffLength` should be invalid if greater than `_endTime - _startTime`
        _cliffLength = uint40(bound(_cliffLength, 0, _endTime > _startTime ? _endTime - _startTime + 1 weeks : 0));

        /// @dev `_amount` should be invalid if zero
        _amount = bound(_amount, 0, TOKEN_100K);

        deal(testToken, address(currentActor), _amount);
        currentActor.approve(testToken, address(govNFT), _amount);

        try
            govNFT.createLock({
                _token: testToken, // creating locks in test token by default
                _recipient: address(currentActor),
                _amount: _amount,
                _startTime: _startTime,
                _endTime: _endTime,
                _cliffLength: _cliffLength,
                _description: ""
            })
        returns (uint256) {
            actorsWithLocks.add(address(currentActor));
            totalDeposited += _amount;
        } catch (bytes memory reason) {
            if (_amount == 0) {
                assertEq(reason, abi.encodeWithSelector(IGovNFT.ZeroAmount.selector));
            } else if (_startTime == _endTime) {
                assertEq(reason, abi.encodeWithSelector(IGovNFT.InvalidParameters.selector));
            } else if (_endTime < _startTime) {
                assertEq(reason, stdError.arithmeticError);
            } else if (_endTime - _startTime < _cliffLength) {
                assertEq(reason, abi.encodeWithSelector(IGovNFT.InvalidCliff.selector));
            } else {
                revert();
            }
        }
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

        uint256 unclaimed = govNFT.unclaimed(_tokenId);
        /// @dev allow amounts slightly larger than unclaimed
        _amount = bound(_amount, 0, unclaimed + unclaimed / 3);

        govNFT.claim({_tokenId: _tokenId, _beneficiary: beneficiary, _amount: _amount});
        /// @dev if `_amount` is greater than `unclaimed`, should only claim `unclaimed`
        idToPersistentClaims[_tokenId] += Math.min(_amount, unclaimed);
    }

    function sweep(
        uint256 _tokenId,
        uint256 _amount,
        uint256 _actorIndex,
        uint256 _beneficiaryActorIndex,
        uint256 _timeskipSeed,
        bool _testInvalidSweep
    ) public useActorWithLocks(_actorIndex) increaseTimestamp(_timeskipSeed) {
        // Select a Random actor to be the Recipient
        address beneficiary = _getRandomActor({_actorSeed: _beneficiaryActorIndex});

        _tokenId = _getRandomLockOfCurrentActor({_tokenIdSeed: _tokenId});

        address token = testToken;
        uint256 end = govNFT.locks(_tokenId).end;
        _amount = bound(_amount, 0, 10 * TOKEN_100K);
        // Can only sweep Lock token if Lock has finished vesting
        if (end >= block.timestamp) {
            // chance of not using airdrop token and getting an InvalidSweep()
            if (!_testInvalidSweep) {
                token = airdropToken;
            } else {
                _amount = 0; // reset amount to avoid dealing tokens in InvalidSweeps
            }
        }
        address vault = govNFT.locks(_tokenId).vault;

        deal(token, vault, IERC20(token).balanceOf(vault) + _amount);
        try govNFT.sweep({_tokenId: _tokenId, _token: token, _recipient: beneficiary, _amount: _amount}) {} catch (
            bytes memory reason
        ) {
            if (end > block.timestamp && token == testToken) {
                assertEq(reason, abi.encodeWithSelector(IGovNFT.InvalidSweep.selector));
            } else if (_amount == 0) {
                assertEq(reason, abi.encodeWithSelector(IGovNFT.ZeroAmount.selector));
            } else {
                revert();
            }
        }
    }

    function split(
        uint256 _tokenId,
        uint256 _amount,
        uint256 _actorIndex,
        uint256 _beneficiaryActorIndex,
        uint256 _timeskipSeed,
        uint8 _splitCount
    ) external useActorWithLocks(_actorIndex) increaseTimestamp(_timeskipSeed) {
        _tokenId = _getRandomLockOfCurrentActor({_tokenIdSeed: _tokenId});

        // Split Lock in `_splitCount` childLocks
        uint40 parentEnd = govNFT.locks(_tokenId).end;
        /// @dev if amount is greater than locked, should revert with AmountTooBig
        uint256 totalSplitAmount = Math.min(govNFT.locked(_tokenId) + 1e18 * 100, TOKEN_100K);
        if (totalSplitAmount > 1 && parentEnd > block.timestamp) {
            // Ensure `totalSplitAmount` can be divided by `_splitCount`
            _splitCount = uint8(bound(_splitCount, 2, Math.min(totalSplitAmount, MAX_SPLITS)));

            IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](_splitCount);
            for (uint256 i = 0; i < _splitCount; i++) {
                // Select a Random actor to be the Recipient
                paramsList[i].beneficiary = _getRandomActor({
                    _actorSeed: uint256((keccak256(abi.encode(_beneficiaryActorIndex, i))))
                });

                // Generate random Split Amount
                paramsList[i].amount = bound({
                    x: uint256(keccak256(abi.encode(_amount, i))),
                    min: 0,
                    max: totalSplitAmount / _splitCount
                });

                // Generate random Timestamp parameters for Child Lock
                (paramsList[i].start, paramsList[i].end, paramsList[i].cliff) = _generateSplitTimestamps({
                    _tokenId: _tokenId,
                    _salt: i
                });
            }
            try govNFT.split({_from: _tokenId, _paramsList: paramsList}) {
                uint256 length = paramsList.length;
                for (uint256 i = 0; i < length; i++) {
                    actorsWithLocks.add(paramsList[i].beneficiary);
                }
            } catch (bytes memory reason) {
                if (!_validateSplits(_tokenId, reason, paramsList)) revert();
            }
        }
    }

    function _validateSplits(
        uint256 tokenId,
        bytes memory reason,
        IGovNFT.SplitParams[] memory paramsList
    ) internal returns (bool) {
        uint256 sum;
        IGovNFT.SplitParams memory params;
        uint256 length = paramsList.length;
        for (uint256 i = 0; i < length; i++) {
            params = paramsList[i];

            if (_validateLockCreation(reason, params.amount, params.start, params.end, params.cliff)) return true;
            if (_validateSplit(tokenId, reason, params.start, params.end, params.cliff)) return true;
            sum += params.amount;
        }
        if (sum > govNFT.locked(tokenId)) {
            assertEq(reason, abi.encodeWithSelector(IGovNFT.AmountTooBig.selector));
            return true;
        }
        return false;
    }

    function _validateLockCreation(
        bytes memory reason,
        uint256 amount,
        uint40 start,
        uint40 end,
        uint40 cliff
    ) internal returns (bool) {
        if (amount == 0) {
            assertEq(reason, abi.encodeWithSelector(IGovNFT.ZeroAmount.selector));
            return true;
        }
        if (start == end) {
            assertEq(reason, abi.encodeWithSelector(IGovNFT.InvalidParameters.selector));
            return true;
        }
        if (end < start) {
            assertEq(reason, stdError.arithmeticError);
            return true;
        }
        if (end - start < cliff) {
            assertEq(reason, abi.encodeWithSelector(IGovNFT.InvalidCliff.selector));
            return true;
        }
        return false;
    }

    function _validateSplit(
        uint256 tokenId,
        bytes memory reason,
        uint40 start,
        uint40 end,
        uint40 cliff
    ) internal returns (bool) {
        IGovNFT.Lock memory parentLock = govNFT.locks(tokenId);
        if (end < parentLock.end) {
            assertEq(reason, abi.encodeWithSelector(IGovNFT.InvalidEnd.selector));
            return true;
        }
        if (start < parentLock.start || start < block.timestamp) {
            assertEq(reason, abi.encodeWithSelector(IGovNFT.InvalidStart.selector));
            return true;
        }
        if (start + cliff < parentLock.start + parentLock.cliffLength) {
            assertEq(reason, abi.encodeWithSelector(IGovNFT.InvalidCliff.selector));
            return true;
        }
        return false;
    }
}
