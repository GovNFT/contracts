// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import "test/invariants/handler/GovNFTHandler.sol";
import {GovNFTSplit} from "src/extensions/GovNFTSplit.sol";

/// @dev Handler for GovNFTSplit contract that creates Locks with larger durations
contract GovNFTSplitHandlerV1 is GovNFTHandler {
    using EnumerableSet for EnumerableSet.AddressSet;

    constructor(
        GovNFTSplit _govNFT,
        TimeStore _timestore,
        address _testToken,
        address _airdropToken,
        uint256 _testActorCount,
        uint256 _initialDeposit,
        uint256 _maxLocks
    ) GovNFTHandler(_govNFT, _timestore, _testToken, _airdropToken, _testActorCount, _initialDeposit, _maxLocks) {}

    // @dev Sets up the Handler contract with an initial 3 year Lock
    function _setUpHandler() internal virtual override {
        deal(testToken, address(this), totalDeposited);
        IERC20(testToken).approve(address(govNFT), totalDeposited);
        // Create initial Lock from which new tokens will be Split
        govNFT.createLock({
            _token: testToken,
            _recipient: address(actors[0]),
            _amount: totalDeposited,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp + 3 * (52 weeks)),
            _cliffLength: 0,
            _description: ""
        });
        actorsWithLocks.add(address(actors[0]));
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
                // @dev Avoid overflow if `parentEnd + 1 weeks > type(uint40).max`
                max: Math.min(uint256(parentEnd) + 1 weeks, type(uint40).max - 1)
            })
        );
        end = uint40(
            bound({
                x: uint256(keccak256(abi.encode(block.timestamp, _salt + 2))),
                min: Math.max(start + 1, parentEnd),
                max: type(uint40).max
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
