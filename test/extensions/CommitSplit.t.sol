// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract CommitSplitTest is BaseTest {
    uint256 public from;
    uint256 public amount;
    uint256 public timelockDelay = 1 days;
    GovNFTTimelock public govNFTLock;

    function _setUp() public override {
        govNFTLock = new GovNFTTimelock({
            _owner: address(admin),
            _artProxy: address(0),
            _name: "GovNFTTimelock",
            _symbol: SYMBOL,
            _earlySweepLockToken: true,
            _timelock: timelockDelay
        });
        // reassigning govNFT to use in helper functions
        govNFT = GovNFTSplit(address(govNFTLock));

        admin.approve(testToken, address(govNFTLock), TOKEN_100K);
        vm.prank(address(admin));
        from = govNFTLock.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_100K,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 3,
            _cliffLength: WEEK
        });
        amount = TOKEN_10K * 4;
    }

    function _checkProposedSplit(uint256 _from, uint256 index, IGovNFT.SplitParams memory params) internal {
        IGovNFT.SplitParams memory proposedParams = govNFTLock.proposedSplits(_from).pendingSplits[index];

        assertEq(proposedParams.beneficiary, params.beneficiary);
        assertEq(proposedParams.amount, params.amount);
        assertEq(proposedParams.start, params.start);
        assertEq(proposedParams.end, params.end);
        assertEq(proposedParams.cliff, params.cliff);
    }

    function test_CommitSplit() public {
        IGovNFT.Lock memory lock = govNFTLock.locks(from);

        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 0);

        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit({
            from: from,
            recipient: address(recipient2),
            splitAmount: amount,
            startTime: lock.start,
            endTime: lock.end
        });
        vm.prank(address(recipient));
        IGovNFT.SplitParams memory params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start,
            end: lock.end,
            cliff: lock.cliffLength
        });
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);

        _checkProposedSplit(from, 0, params);
        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 1);
        assertEq(govNFTLock.proposedSplits(from).timestamp, uint40(block.timestamp));
    }

    function testFuzz_CommitSplit(uint40 deltaStart, uint40 deltaEnd, uint40 cliff) public {
        deltaStart = uint40(bound(deltaStart, 0, WEEK * 9));
        IGovNFT.Lock memory lock = govNFTLock.locks(from);
        uint40 newStart = lock.start + deltaStart;

        deltaEnd = uint40(bound(deltaEnd, Math.max(newStart, lock.end), WEEK * 9));

        uint40 newEnd = lock.end + deltaEnd;

        uint40 duration = newEnd - newStart;
        uint40 remainingCliff = deltaStart <= lock.cliffLength ? lock.cliffLength - deltaStart : 0;
        cliff = uint40(bound(cliff, remainingCliff, Math.min(duration, newEnd)));

        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 0);

        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit({
            from: from,
            recipient: address(recipient2),
            splitAmount: amount,
            startTime: newStart,
            endTime: newEnd
        });
        vm.prank(address(recipient));
        IGovNFT.SplitParams memory params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: newStart,
            end: newEnd,
            cliff: cliff
        });
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);

        _checkProposedSplit(from, 0, params);
        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 1);
        assertEq(govNFTLock.proposedSplits(from).timestamp, uint40(block.timestamp));
    }

    function test_BatchCommitSplit() public {
        IGovNFT.Lock memory lock = govNFTLock.locks(from);

        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 0);

        amount = TOKEN_1 * 1000;
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](5);
        // same timestamps as parent token
        // split timestamps can be the same as parent token because vesting has not started
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount,
            start: lock.start,
            end: lock.end,
            cliff: lock.cliffLength
        });
        // extending end timestamp
        paramsList[1] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount * 2,
            start: lock.start,
            end: lock.end + 3 * WEEK,
            cliff: lock.cliffLength
        });
        // extending start timestamp
        paramsList[2] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount + amount / 2,
            start: lock.start + WEEK / 2,
            end: lock.end,
            cliff: lock.cliffLength
        });
        // extending cliff period
        paramsList[3] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount / 2,
            start: lock.start,
            end: lock.end,
            cliff: lock.cliffLength * 2
        });
        // extending start and decreasing cliff
        paramsList[4] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount * 3,
            start: lock.start + WEEK / 2,
            end: lock.end,
            cliff: lock.cliffLength - WEEK / 2
        });
        for (uint256 i = 0; i < paramsList.length; i++) {
            // each split decreases the parent's `totalLocked` value by `amount`
            vm.expectEmit(true, true, false, true);
            emit IGovNFTTimelock.CommitSplit({
                from: from,
                recipient: paramsList[i].beneficiary,
                splitAmount: paramsList[i].amount,
                startTime: paramsList[i].start,
                endTime: paramsList[i].end
            });
        }
        vm.prank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        uint256 splitLength = paramsList.length;
        assertEq(govNFTLock.proposedSplits(from).timestamp, uint40(block.timestamp));
        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, splitLength);

        for (uint256 i = 0; i < splitLength; i++) {
            _checkProposedSplit(from, i, paramsList[i]);
        }
    }

    function test_CommitSplitOverridesPreviousCommit() public {
        IGovNFT.Lock memory lock = govNFTLock.locks(from);

        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 0);

        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit({
            from: from,
            recipient: address(recipient2),
            splitAmount: amount,
            startTime: lock.start,
            endTime: lock.end
        });
        vm.startPrank(address(recipient));
        IGovNFT.SplitParams memory params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start,
            end: lock.end,
            cliff: lock.cliffLength
        });
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);

        _checkProposedSplit(from, 0, params);
        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 1);
        assertEq(govNFTLock.proposedSplits(from).timestamp, uint40(block.timestamp));

        params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount / 2,
            start: lock.start + WEEK,
            end: lock.end + WEEK,
            cliff: lock.cliffLength + WEEK
        });
        paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);

        _checkProposedSplit(from, 0, params);
        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 1);
        assertEq(govNFTLock.proposedSplits(from).timestamp, uint40(block.timestamp));
    }

    function test_BatchCommitSplitOverridesPreviousCommit() public {
        IGovNFT.Lock memory lock = govNFTLock.locks(from);

        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 0);

        amount = TOKEN_1 * 1000;
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](5);
        // same timestamps as parent token
        // split timestamps can be the same as parent token because vesting has not started
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount,
            start: lock.start,
            end: lock.end,
            cliff: lock.cliffLength
        });
        // extending end timestamp
        paramsList[1] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount * 2,
            start: lock.start,
            end: lock.end + 3 * WEEK,
            cliff: lock.cliffLength
        });
        // extending start timestamp
        paramsList[2] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount + amount / 2,
            start: lock.start + WEEK / 2,
            end: lock.end,
            cliff: lock.cliffLength
        });
        // extending cliff period
        paramsList[3] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount / 2,
            start: lock.start,
            end: lock.end,
            cliff: lock.cliffLength * 2
        });
        // extending start and decreasing cliff
        paramsList[4] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount * 3,
            start: lock.start + WEEK / 2,
            end: lock.end,
            cliff: lock.cliffLength - WEEK / 2
        });
        for (uint256 i = 0; i < paramsList.length; i++) {
            // each split decreases the parent's `totalLocked` value by `amount`
            vm.expectEmit(true, true, false, true);
            emit IGovNFTTimelock.CommitSplit({
                from: from,
                recipient: paramsList[i].beneficiary,
                splitAmount: paramsList[i].amount,
                startTime: paramsList[i].start,
                endTime: paramsList[i].end
            });
        }
        vm.prank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        uint256 splitLength = paramsList.length;
        assertEq(govNFTLock.proposedSplits(from).timestamp, uint40(block.timestamp));
        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, splitLength);

        for (uint256 i = 0; i < splitLength; i++) {
            _checkProposedSplit(from, i, paramsList[i]);
        }

        paramsList = new IGovNFT.SplitParams[](4);
        // same timestamps as parent token
        // split timestamps can be the same as parent token because vesting has not started
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount / 2,
            start: lock.start + WEEK,
            end: lock.end + WEEK,
            cliff: lock.cliffLength + WEEK
        });
        // extending end timestamp
        paramsList[1] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount * 3,
            start: lock.start + 1 days,
            end: lock.end + 2 * WEEK,
            cliff: lock.cliffLength - 1 days
        });
        // extending start timestamp
        paramsList[2] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount * 2,
            start: lock.start + WEEK / 2,
            end: lock.end,
            cliff: lock.cliffLength
        });
        // extending cliff period
        paramsList[3] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount,
            start: lock.start + WEEK / 2,
            end: lock.end + WEEK,
            cliff: lock.cliffLength - WEEK / 3
        });
        for (uint256 i = 0; i < paramsList.length; i++) {
            // each split decreases the parent's `totalLocked` value by `amount`
            vm.expectEmit(true, true, false, true);
            emit IGovNFTTimelock.CommitSplit({
                from: from,
                recipient: paramsList[i].beneficiary,
                splitAmount: paramsList[i].amount,
                startTime: paramsList[i].start,
                endTime: paramsList[i].end
            });
        }
        vm.prank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        // Split length has decreased because second `paramsList` is smaller
        splitLength = paramsList.length;
        assertEq(govNFTLock.proposedSplits(from).timestamp, uint40(block.timestamp));
        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, splitLength);

        for (uint256 i = 0; i < splitLength; i++) {
            _checkProposedSplit(from, i, paramsList[i]);
        }
    }

    function test_BatchCommitSplitDeletedAfterTransfer() public {
        IGovNFT.Lock memory lock = govNFTLock.locks(from);

        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 0);

        amount = TOKEN_1 * 1000;
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](5);
        // same timestamps as parent token
        // split timestamps can be the same as parent token because vesting has not started
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount,
            start: lock.start,
            end: lock.end,
            cliff: lock.cliffLength
        });
        // extending end timestamp
        paramsList[1] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount * 2,
            start: lock.start,
            end: lock.end + 3 * WEEK,
            cliff: lock.cliffLength
        });
        // extending start timestamp
        paramsList[2] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount + amount / 2,
            start: lock.start + WEEK / 2,
            end: lock.end,
            cliff: lock.cliffLength
        });
        // extending cliff period
        paramsList[3] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount / 2,
            start: lock.start,
            end: lock.end,
            cliff: lock.cliffLength * 2
        });
        // extending start and decreasing cliff
        paramsList[4] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount * 3,
            start: lock.start + WEEK / 2,
            end: lock.end,
            cliff: lock.cliffLength - WEEK / 2
        });
        for (uint256 i = 0; i < paramsList.length; i++) {
            // each split decreases the parent's `totalLocked` value by `amount`
            vm.expectEmit(true, true, false, true);
            emit IGovNFTTimelock.CommitSplit({
                from: from,
                recipient: paramsList[i].beneficiary,
                splitAmount: paramsList[i].amount,
                startTime: paramsList[i].start,
                endTime: paramsList[i].end
            });
        }
        vm.prank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        uint256 splitLength = paramsList.length;
        assertEq(govNFTLock.proposedSplits(from).timestamp, uint40(block.timestamp));
        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, splitLength);

        for (uint256 i = 0; i < splitLength; i++) {
            _checkProposedSplit(from, i, paramsList[i]);
        }

        vm.prank(address(recipient));
        govNFTLock.transferFrom(address(recipient), address(recipient2), from);

        // After transferring the NFT, there are no longer pending splits
        assertEq(govNFTLock.proposedSplits(from).timestamp, 0);
        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 0);
    }

    function test_CommitSplitPermissions() public {
        IGovNFT.Lock memory lock = govNFTLock.locks(from);
        assertEq(lock.minter, address(admin));

        address approvedUser = makeAddr("alice");
        assertEq(govNFTLock.balanceOf(approvedUser), 0);

        vm.prank(address(recipient));
        govNFTLock.approve(approvedUser, from);

        // can split after getting approval on nft
        vm.prank(approvedUser);
        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit({
            from: from,
            recipient: approvedUser,
            splitAmount: TOKEN_1,
            startTime: lock.start,
            endTime: lock.end
        });
        IGovNFT.SplitParams memory params = IGovNFT.SplitParams({
            beneficiary: approvedUser,
            amount: TOKEN_1,
            start: uint40(block.timestamp),
            end: uint40(block.timestamp) + 3 * WEEK,
            cliff: WEEK
        });
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);

        address approvedForAllUser = makeAddr("bob");
        assertEq(govNFTLock.balanceOf(approvedForAllUser), 0);

        vm.prank(address(recipient));
        govNFTLock.setApprovalForAll(approvedForAllUser, true);

        // can split after getting approval for all nfts
        vm.prank(approvedForAllUser);
        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit({
            from: from,
            recipient: approvedForAllUser,
            splitAmount: TOKEN_1,
            startTime: lock.start,
            endTime: lock.end
        });
        params = IGovNFT.SplitParams({
            beneficiary: approvedForAllUser,
            amount: TOKEN_1,
            start: uint40(block.timestamp),
            end: uint40(block.timestamp) + 3 * WEEK,
            cliff: WEEK
        });
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);
    }

    function test_RevertIf_CommitSplitIfNotRecipientOrApproved() public {
        address testUser = makeAddr("alice");

        vm.prank(testUser);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, testUser, from));
        IGovNFT.SplitParams memory params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: TOKEN_1,
            start: uint40(block.timestamp),
            end: uint40(block.timestamp) + 3 * WEEK,
            cliff: WEEK
        });
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);

        vm.prank(address(admin));
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(admin), from)
        );
        govNFTLock.commitSplit(from, paramsList);
    }

    function test_RevertIf_CommitSplitNonExistentToken() public {
        uint256 tokenId = from + 2;
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
        vm.prank(address(recipient));
        IGovNFT.SplitParams memory params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: TOKEN_1,
            start: uint40(block.timestamp),
            end: uint40(block.timestamp) + 3 * WEEK,
            cliff: WEEK
        });
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = params;
        govNFTLock.commitSplit(tokenId, paramsList);
    }

    function test_RevertIf_CommitSplitIfZeroAmount() public {
        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.ZeroAmount.selector);
        IGovNFT.SplitParams memory params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: 0,
            start: uint40(block.timestamp),
            end: uint40(block.timestamp) + 3 * WEEK,
            cliff: WEEK
        });
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);
    }

    function test_RevertIf_CommitSplitIfInvalidStart() public {
        IGovNFT.Lock memory lock = govNFTLock.locks(from);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.InvalidStart.selector);
        // new vesting cannot start before original vesting starts
        IGovNFT.SplitParams memory params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start - 1,
            end: lock.end,
            cliff: lock.cliffLength
        });
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);

        skip(WEEK + 1 days); //skip to after vesting start

        // start cannot be before block.timestamp, even if after original vesting starts
        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.InvalidStart.selector);
        params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start + 1,
            end: lock.end,
            cliff: lock.cliffLength
        });
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.InvalidStart.selector);
        params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: uint40(block.timestamp) - 1,
            end: lock.end,
            cliff: lock.cliffLength
        });
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);
    }

    function test_RevertIf_CommitSplitWithInvalidEnd() public {
        IGovNFT.Lock memory lock = govNFTLock.locks(from);

        vm.startPrank(address(recipient));
        IGovNFT.SplitParams memory params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: uint40(block.timestamp),
            end: lock.end - 1,
            cliff: lock.cliffLength
        });
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = params;

        // cannot split if proposed end is before `parentLock.end`
        vm.expectRevert(IGovNFT.InvalidEnd.selector);
        govNFTLock.commitSplit(from, paramsList);
    }

    function test_RevertIf_CommitSplitWithAmountTooBig() public {
        IGovNFT.Lock memory lock = govNFTLock.locks(from);

        vm.startPrank(address(recipient));
        // cannot propose split with amount higher than totallock
        IGovNFT.SplitParams memory params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: lock.totalLocked + 1,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: lock.cliffLength
        });
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = params;

        vm.expectRevert(IGovNFT.AmountTooBig.selector);
        govNFTLock.commitSplit(from, paramsList);

        vm.warp(lock.end); // warp to end of `parentLock` vesting period

        // cannot propose split if `parentLock` has finished vesting
        vm.expectRevert(IGovNFT.AmountTooBig.selector);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: TOKEN_1,
            start: uint40(block.timestamp),
            end: lock.end + WEEK,
            cliff: lock.cliffLength
        });
        govNFTLock.commitSplit(from, paramsList);
        vm.stopPrank();
    }

    function test_RevertIf_CommitSplitWithAmountTooBigMultipleSplits() public {
        IGovNFT.Lock memory lock = govNFTLock.locks(from);

        vm.startPrank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](2);
        // sum of amounts should not be greater than totallocked
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: (lock.totalLocked + TOKEN_1) / 2,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: lock.cliffLength
        });
        paramsList[1] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: (lock.totalLocked + TOKEN_1) / 2,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: lock.cliffLength
        });

        vm.expectRevert(IGovNFT.AmountTooBig.selector);
        govNFTLock.commitSplit(from, paramsList);

        // skip some time to vest tokens
        skip((lock.end - lock.start) / 2);

        uint256 lockedAmount = govNFTLock.locked(from);

        // sum of amounts should not be greater than locked value
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: (lockedAmount + TOKEN_1) / 2,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: lock.cliffLength
        });
        paramsList[1] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: (lockedAmount + TOKEN_1) / 2,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: lock.cliffLength
        });

        vm.expectRevert(IGovNFT.AmountTooBig.selector);
        govNFTLock.commitSplit(from, paramsList);
        vm.stopPrank();
    }

    function test_RevertIf_CommitSplitIfEndBeforeOrEqualStart() public {
        IGovNFT.Lock memory lock = govNFTLock.locks(from);

        vm.prank(address(recipient));
        vm.expectRevert(stdError.arithmeticError);
        IGovNFT.SplitParams memory params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.end + 1,
            end: lock.end,
            cliff: 0
        });
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.InvalidParameters.selector);
        params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.end,
            end: lock.end,
            cliff: 0
        });
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);
    }

    function test_RevertIf_CommitSplitIfInvalidCliff() public {
        IGovNFT.Lock memory lock = govNFTLock.locks(from);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.InvalidCliff.selector);
        IGovNFT.SplitParams memory params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start,
            end: lock.end,
            cliff: lock.cliffLength - 1
        });
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.InvalidCliff.selector);
        params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.end - lock.cliffLength / 2,
            end: lock.end,
            cliff: lock.cliffLength
        });
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);
    }

    function test_RevertIf_CommitSplitZeroAddress() public {
        IGovNFT.Lock memory lock = govNFTLock.locks(from);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.ZeroAddress.selector);
        IGovNFT.SplitParams memory params = IGovNFT.SplitParams({
            beneficiary: address(0),
            amount: amount,
            start: lock.start,
            end: lock.end,
            cliff: lock.cliffLength
        });
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);
    }
}
