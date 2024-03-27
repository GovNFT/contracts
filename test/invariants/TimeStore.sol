// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

/// @dev Because Foundry does not commit the state changes between invariant runs, we need to
///      save the current timestamp in a contract with persistent storage.
contract TimeStore {
    uint256 public currentTimestamp;
    uint256 public currentBlockNumber;
    uint256 public secondsPerBlock;

    constructor(uint256 _secondsPerBlock) {
        currentTimestamp = block.timestamp;
        currentBlockNumber = block.number;
        secondsPerBlock = _secondsPerBlock;
    }

    function increaseCurrentTimestamp(uint256 timeskip) external {
        currentTimestamp += timeskip;
        currentBlockNumber += (timeskip / secondsPerBlock);
    }

    function increaseCurrentBlockNumber(uint256 blockJump) external {
        currentTimestamp += blockJump * secondsPerBlock;
        currentBlockNumber += blockJump;
    }
}
