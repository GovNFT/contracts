// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract BatchSplitTest is BaseTest {
    uint256 public from;
    uint256 public amount;

    function _setUp() public override {
        deal(testToken, address(admin), TOKEN_10M);
        admin.approve(testToken, address(govNFT), TOKEN_10M);
        vm.prank(address(admin));
        from = govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_10M,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 3,
            _cliffLength: WEEK,
            _description: ""
        });
        amount = TOKEN_10K * 3;

        // no prior splits or unclaimed rewards
        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.splitCount, 0);
    }

    function test_BatchSplitBeforeStart() public {
        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.totalLocked, govNFT.locked(from)); // no tokens have been vested before splitting
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked);

        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](5);
        // same timestamps as parent token
        // split timestamps can be the same as parent token because vesting has not started
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount,
            start: lock.start,
            end: lock.end,
            cliff: lock.cliffLength,
            description: ""
        });
        // extending end timestamp
        paramsList[1] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount * 2,
            start: lock.start,
            end: lock.end + 3 * WEEK,
            cliff: lock.cliffLength,
            description: ""
        });
        // extending start timestamp
        paramsList[2] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount + amount / 2,
            start: lock.start + WEEK / 2,
            end: lock.end,
            cliff: lock.cliffLength,
            description: ""
        });
        // extending cliff period
        paramsList[3] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount / 2,
            start: lock.start,
            end: lock.end,
            cliff: lock.cliffLength * 2,
            description: ""
        });
        // extending start and decreasing cliff
        paramsList[4] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount * 3,
            start: lock.start + WEEK / 2,
            end: lock.end,
            cliff: lock.cliffLength - WEEK / 2,
            description: ""
        });

        uint256 splitLockAmounts;
        for (uint256 i = 0; i < paramsList.length; i++) {
            // each split decreases the parent's `totalLocked` value by `amount`
            splitLockAmounts += paramsList[i].amount;
            vm.expectEmit(true, true, true, true);
            emit IGovNFT.Split({
                from: from,
                to: from + (i + 1),
                recipient: paramsList[i].beneficiary,
                splitAmount1: lock.totalLocked - splitLockAmounts,
                splitAmount2: paramsList[i].amount,
                startTime: paramsList[i].start,
                endTime: paramsList[i].end,
                description: ""
            });
        }
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);

        uint256 oldSupply = govNFT.totalSupply();

        vm.prank(address(recipient));
        uint256[] memory tokenIds = govNFT.split(from, paramsList);

        assertEq(tokenIds.length, paramsList.length);
        assertEq(govNFT.totalSupply(), oldSupply + paramsList.length);

        // check updates on parent lock
        _checkLockUpdates({
            tokenId: from,
            _totalLocked: lock.totalLocked - splitLockAmounts,
            _initialDeposit: lock.totalLocked,
            _cliffLength: lock.cliffLength,
            _start: lock.start,
            _end: lock.end
        });
        for (uint256 i = 0; i < paramsList.length; i++) {
            // check split info and lock updates on all split locks
            _checkBatchSplitInfo({
                _from: from,
                tokenId: tokenIds[i],
                owner: address(recipient),
                beneficiary: paramsList[i].beneficiary,
                unclaimedBeforeSplit: 0,
                splitCount: uint40(paramsList.length),
                splitIndex: i
            });
            _checkLockUpdates({
                tokenId: tokenIds[i],
                _totalLocked: paramsList[i].amount,
                _initialDeposit: paramsList[i].amount,
                _cliffLength: paramsList[i].cliff,
                _start: paramsList[i].start,
                _end: paramsList[i].end
            });
        }
    }

    function test_BatchSplitBeforeCliffEnd() public {
        skip(2 days); // skip somewhere before cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.totalLocked, govNFT.locked(from)); // still on cliff, no tokens vested
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked);

        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](5);
        // same timestamps as parent token
        // `start` has to be greater than `block.timestamp` since vest has already started
        uint40 timestamp = uint40(block.timestamp);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount,
            start: timestamp,
            end: lock.end,
            cliff: lock.cliffLength - 2 days,
            description: ""
        });
        // extending end timestamp
        paramsList[1] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount / 2,
            start: timestamp,
            end: lock.end + 3 * WEEK,
            cliff: lock.cliffLength - 2 days,
            description: ""
        });
        // extending start timestamp
        paramsList[2] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount + amount / 2,
            start: timestamp + WEEK / 2,
            end: lock.end,
            cliff: lock.cliffLength - 2 days,
            description: ""
        });
        // extending cliff period
        paramsList[3] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount,
            start: timestamp,
            end: lock.end,
            cliff: (lock.cliffLength - 2 days) * 2,
            description: ""
        });
        // extending start and decreasing cliff
        paramsList[4] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount * 3,
            start: timestamp + 2 days,
            end: lock.end,
            cliff: lock.cliffLength - 4 days,
            description: ""
        });

        uint256 splitLockAmounts;
        for (uint256 i = 0; i < paramsList.length; i++) {
            // each split decreases the parent's `totalLocked` value by `amount`
            splitLockAmounts += paramsList[i].amount;
            vm.expectEmit(true, true, true, true);
            emit IGovNFT.Split({
                from: from,
                to: from + (i + 1),
                recipient: paramsList[i].beneficiary,
                splitAmount1: lock.totalLocked - splitLockAmounts,
                splitAmount2: paramsList[i].amount,
                startTime: paramsList[i].start,
                endTime: paramsList[i].end,
                description: ""
            });
        }
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);

        uint256 oldSupply = govNFT.totalSupply();

        vm.prank(address(recipient));
        uint256[] memory tokenIds = govNFT.split(from, paramsList);

        assertEq(tokenIds.length, paramsList.length);
        assertEq(govNFT.totalSupply(), oldSupply + paramsList.length);

        // original NFT assertions
        uint40 remainingCliff = (lock.start + lock.cliffLength) - uint40(block.timestamp);
        assertEq(remainingCliff, WEEK - 2 days);
        // since still on cliff and vesting has started, the split cliff length will be
        // the remaining cliff period and the new start will be the current timestamp
        _checkLockUpdates({
            tokenId: from,
            _totalLocked: lock.totalLocked - splitLockAmounts,
            _initialDeposit: lock.totalLocked,
            _cliffLength: remainingCliff,
            _start: uint40(block.timestamp),
            _end: lock.end
        });
        for (uint256 i = 0; i < paramsList.length; i++) {
            // check split info and lock updates on all split locks
            _checkBatchSplitInfo({
                _from: from,
                tokenId: tokenIds[i],
                owner: address(recipient),
                beneficiary: paramsList[i].beneficiary,
                unclaimedBeforeSplit: 0,
                splitCount: uint40(paramsList.length),
                splitIndex: i
            });
            _checkLockUpdates({
                tokenId: tokenIds[i],
                _totalLocked: paramsList[i].amount,
                _initialDeposit: paramsList[i].amount,
                _cliffLength: paramsList[i].cliff,
                _start: paramsList[i].start,
                _end: paramsList[i].end
            });
        }
    }

    function test_BatchSplitAfterCliffEnd() public {
        skip(WEEK + 2 days); // skip somewhere after cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked);

        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](5);
        // same timestamps as parent token
        // no cliff since vesting has already started
        uint40 timestamp = uint40(block.timestamp);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount,
            start: timestamp,
            end: lock.end,
            cliff: 0,
            description: ""
        });
        // extending end timestamp
        paramsList[1] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount / 2,
            start: timestamp,
            end: lock.end + 3 * WEEK,
            cliff: 0,
            description: ""
        });
        // extending start timestamp
        paramsList[2] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount + amount / 2,
            start: timestamp + WEEK / 2,
            end: lock.end,
            cliff: 0,
            description: ""
        });
        // extending cliff period
        paramsList[3] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount,
            start: timestamp,
            end: lock.end,
            cliff: WEEK / 2,
            description: ""
        });
        // extending start and cliff
        paramsList[4] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount * 3,
            start: timestamp + WEEK,
            end: lock.end,
            cliff: WEEK / 2,
            description: ""
        });

        uint256 splitLockAmounts;
        for (uint256 i = 0; i < paramsList.length; i++) {
            // each split decreases the parent's `locked` value by `amount`
            splitLockAmounts += paramsList[i].amount;
            vm.expectEmit(true, true, true, true);
            emit IGovNFT.Split({
                from: from,
                to: from + (i + 1),
                recipient: paramsList[i].beneficiary,
                splitAmount1: lockedBeforeSplit - splitLockAmounts,
                splitAmount2: paramsList[i].amount,
                startTime: paramsList[i].start,
                endTime: paramsList[i].end,
                description: ""
            });
        }
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);

        uint256 oldSupply = govNFT.totalSupply();

        vm.prank(address(recipient));
        uint256[] memory tokenIds = govNFT.split(from, paramsList);

        assertEq(tokenIds.length, paramsList.length);
        assertEq(govNFT.totalSupply(), oldSupply + paramsList.length);

        // original NFT assertions
        // no cliff since vesting has already started
        _checkLockUpdates({
            tokenId: from,
            _totalLocked: lockedBeforeSplit - splitLockAmounts,
            _initialDeposit: lock.totalLocked,
            _cliffLength: 0,
            _start: uint40(block.timestamp),
            _end: lock.end
        });
        for (uint256 i = 0; i < paramsList.length; i++) {
            // check split info and lock updates on all split locks
            _checkBatchSplitInfo({
                _from: from,
                tokenId: tokenIds[i],
                owner: address(recipient),
                beneficiary: paramsList[i].beneficiary,
                unclaimedBeforeSplit: originalUnclaimed,
                splitCount: uint40(paramsList.length),
                splitIndex: i
            });
            _checkLockUpdates({
                tokenId: tokenIds[i],
                _totalLocked: paramsList[i].amount,
                _initialDeposit: paramsList[i].amount,
                _cliffLength: paramsList[i].cliff,
                _start: paramsList[i].start,
                _end: paramsList[i].end
            });
        }
        assertEq(govNFT.locked(from), govNFT.locks(from).totalLocked);
    }

    function test_RevertIf_BatchSplitSumIsGreaterThanParentLock() public {
        IGovNFT.Lock memory lock = govNFT.locks(from);
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](5);
        for (uint256 i = 0; i < paramsList.length; i++) {
            // reverts when sum of amounts is greater than total locked
            paramsList[i] = IGovNFT.SplitParams({
                beneficiary: address(recipient),
                amount: (lock.totalLocked + TOKEN_1) / paramsList.length,
                start: lock.start,
                end: lock.end,
                cliff: lock.cliffLength,
                description: ""
            });
        }
        vm.expectRevert(IGovNFT.AmountTooBig.selector);
        vm.prank(address(recipient));
        govNFT.split(from, paramsList);
    }

    function test_RevertIf_BatchSplitWithNoParameters() public {
        IGovNFT.SplitParams[] memory paramsList;
        assertEq(paramsList.length, 0);

        vm.expectRevert(IGovNFT.InvalidParameters.selector);
        vm.prank(address(recipient));
        govNFT.split(from, paramsList);
    }

    function test_RevertIf_BatchSplitWithUninitializedParameters() public {
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](2);
        assertEq(paramsList.length, 2);

        vm.expectRevert(IGovNFT.InvalidStart.selector);
        vm.prank(address(recipient));
        govNFT.split(from, paramsList);
    }
}
