// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/invariants/handler/GovNFTHandler.sol";
import {GovNFT} from "src/GovNFT.sol";

/// @dev Handler for GovNFT contract that creates Locks with short durations
contract GovNFTHandlerV2 is GovNFTHandler {
    using EnumerableSet for EnumerableSet.AddressSet;

    constructor(
        GovNFT _govNFT,
        TimeStore _timestore,
        address _testToken,
        address _airdropToken,
        uint256 _testActorCount,
        uint256 _initialDeposit,
        uint256 _maxLocks
    ) GovNFTHandler(_govNFT, _timestore, _testToken, _airdropToken, _testActorCount, _initialDeposit, _maxLocks) {}

    // @dev Sets up the Handler contract with initial small duration Locks
    function _setUpHandler() internal virtual override {
        deal(testToken, address(this), totalDeposited);
        IERC20(testToken).approve(address(govNFT), totalDeposited);
        // Create new 2 month Lock from which new tokens will be Split
        uint256 tokenId = govNFT.createLock({
            _token: testToken,
            _recipient: address(actors[0]),
            _amount: totalDeposited,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp + 2 * (4 weeks)),
            _cliffLength: 0,
            _description: ""
        });
        actorsWithLocks.add(address(actors[0]));

        // Create additional Locks with small durations via Split
        _splitInitialLock(tokenId);

        // Skip forward in time to allow locks to expire earlier
        timestore.increaseCurrentTimestamp({timeskip: 4 weeks});
        vm.warp(timestore.currentTimestamp());
        vm.roll(timestore.currentBlockNumber());
    }

    function _splitInitialLock(uint256 _tokenId) internal {
        // Create additional Locks with small durations via Split
        uint256 parentEnd = govNFT.locks(_tokenId).end;
        IGovNFT.SplitParams[] memory params = new IGovNFT.SplitParams[](2);
        for (uint256 i = 0; i < params.length; i++) {
            params[i].beneficiary = address(actors[(i + 1) % actors.length]);
            actorsWithLocks.add(params[i].beneficiary);

            params[i].amount = bound({
                x: uint256((keccak256(abi.encode(params[i].beneficiary, i)))),
                min: 1,
                max: TOKEN_100K
            });
            params[i].start = uint40(
                bound({
                    x: uint256(keccak256(abi.encode(params[i].beneficiary, i + 1))),
                    min: block.timestamp,
                    max: block.timestamp + 8 weeks
                })
            );
            params[i].end = uint40(
                bound({
                    x: uint256(keccak256(abi.encode(params[i].beneficiary, i + 2))),
                    min: parentEnd,
                    max: parentEnd + 8 weeks
                })
            );
            params[i].cliff = uint40(
                bound({
                    x: uint256(keccak256(abi.encode(params[i].beneficiary, i + 3))),
                    min: 0,
                    max: params[i].end - params[i].start
                })
            );
        }
        vm.prank(address(actors[0]));
        GovNFT(address(govNFT)).split(_tokenId, params);
    }

    function _generateSplitTimestamps(
        uint256 _tokenId,
        uint256 _salt
    ) internal view virtual override returns (uint40 start, uint40 end, uint40 cliff) {
        IGovNFT.Lock memory lock = govNFT.locks(_tokenId);
        uint40 parentEnd = lock.end;
        uint40 parentStart = lock.start;
        uint40 parentCliffEnd = parentStart + lock.cliffLength;
        start = uint40(
            bound({
                x: uint256(keccak256(abi.encode(block.timestamp, _salt + 1))),
                min: Math.max(parentStart, block.timestamp),
                // @dev Avoid overflow if `parentEnd + 6 weeks > type(uint40).max`
                max: Math.min(uint256(parentEnd) + 6 weeks, type(uint40).max - 1)
            })
        );
        uint256 min = Math.max(start + 1, parentEnd);
        end = uint40(
            bound({
                x: uint256(keccak256(abi.encode(block.timestamp, _salt + 2))),
                min: min,
                max: min + 3 * (4 weeks) // max delta is 3 months
            })
        );
        cliff = uint40(
            bound({
                x: uint256(keccak256(abi.encode(block.timestamp, _salt + 3))),
                // If new start is before parent's cliff end, need to account for remaining cliff
                min: start < parentCliffEnd ? parentCliffEnd - start : 0,
                max: end - start
            })
        );
    }
}
