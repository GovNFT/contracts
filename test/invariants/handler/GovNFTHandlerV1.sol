// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/invariants/handler/GovNFTHandler.sol";
import {GovNFT} from "src/GovNFT.sol";

/// @dev Handler for GovNFT contract that creates Locks with larger durations
contract GovNFTHandlerV1 is GovNFTHandler {
    using EnumerableSet for EnumerableSet.AddressSet;

    constructor(
        GovNFT _govNFT,
        TimeStore _timestore,
        address _testToken,
        address _airdropToken,
        uint256 _testActorCount,
        uint256 _initialDeposit
    ) GovNFTHandler(_govNFT, _timestore, _testToken, _airdropToken, _testActorCount, _initialDeposit) {}

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
        /// @dev `start` should be invalid if smaller or equal to `parentStart` or `block.timestamp`
        start = uint40(
            bound({
                x: uint256(keccak256(abi.encode(block.timestamp, _salt + 1))),
                min: Math.max(parentStart - 1 weeks, block.timestamp - 1 weeks),
                // @dev Avoid overflow if `parentEnd + 2 weeks > type(uint40).max`
                max: Math.min(uint256(parentEnd) + 2 weeks, type(uint40).max - 1)
            })
        );
        /// @dev `end` should be invalid if smaller or equal to `start` or `parentEnd`
        end = uint40(
            bound({
                x: uint256(keccak256(abi.encode(block.timestamp, _salt + 2))),
                min: Math.max(start - 2 weeks, parentEnd > 2 weeks ? parentEnd - 2 weeks : parentEnd),
                max: type(uint40).max
            })
        );
        if (end <= start) {
            cliff = 0; // If invalid start and end, no cliff is necessary
        } else {
            // If new start is before parent's cliff end, need to account for remaining cliff
            uint256 min = start < parentCliffEnd ? parentCliffEnd - start : 0;
            /// @dev `cliff` should be invalid if greater than lock duration or smaller than remaining cliff
            cliff = uint40(
                bound({
                    x: uint256(keccak256(abi.encode(block.timestamp, _salt + 3))),
                    min: min > 1 weeks ? min - 1 weeks : min, // allow smaller values to test invalid cliffs
                    max: end - start + 2 weeks
                })
            );
        }
    }
}
