// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import {IERC721Errors} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";

import "test/utils/BaseTest.sol";

contract CommitSplitTest is BaseTest {
    uint256 public from;
    uint256 public amount;
    uint256 public timelockDelay = 1 days;
    GovNFTTimelock public govNFTLock;

    function _setUp() public override {
        govNFTLock = new GovNFTTimelock(address(admin), address(0), "GovNFTTimelock", "GovNFT", timelockDelay);
        // reassigning govNFT to use in helper functions
        govNFT = GovNFTSplit(address(govNFTLock));

        admin.approve(testToken, address(govNFTLock), TOKEN_100K);
        vm.prank(address(admin));
        from = govNFTLock.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 3,
            WEEK
        );
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
        (, , , , , uint256 cliffLength, uint256 start, uint256 end, , , ) = govNFTLock.locks(from);

        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 0);

        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit(from, address(recipient2), amount, start, end);
        vm.prank(address(recipient));
        IGovNFT.SplitParams memory params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: start,
            end: end,
            cliff: cliffLength
        });
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);

        _checkProposedSplit(from, 0, params);
        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 1);
        assertEq(govNFTLock.proposedSplits(from).timestamp, block.timestamp);
    }

    function test_FuzzCommitSplit(uint40 deltaStart, uint40 deltaEnd, uint40 cliff) public {
        deltaStart = uint40(bound(deltaStart, 0, WEEK * 9));
        (, , , , , uint256 cliffLength, uint256 start, uint256 end, , , ) = govNFTLock.locks(from);
        uint256 newStart = start + deltaStart;

        deltaEnd = uint40(bound(deltaEnd, Math.max(newStart, end), WEEK * 9));

        uint256 newEnd = end + deltaEnd;

        uint256 duration = newEnd - newStart;
        uint256 remainingCliff = deltaStart <= cliffLength ? cliffLength - deltaStart : 0;
        cliff = uint40(bound(cliff, remainingCliff, Math.min(duration, newEnd)));

        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 0);

        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit(from, address(recipient2), amount, newStart, newEnd);
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
        assertEq(govNFTLock.proposedSplits(from).timestamp, block.timestamp);
    }

    function test_BatchCommitSplit() public {
        (, , , , , uint256 cliffLength, uint256 start, uint256 end, , , ) = govNFTLock.locks(from);

        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 0);

        amount = TOKEN_1 * 1000;
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](5);
        // same timestamps as parent token
        // split timestamps can be the same as parent token because vesting has not started
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount,
            start: start,
            end: end,
            cliff: cliffLength
        });
        // extending end timestamp
        paramsList[1] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount * 2,
            start: start,
            end: end + 3 * WEEK,
            cliff: cliffLength
        });
        // extending start timestamp
        paramsList[2] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount + amount / 2,
            start: start + WEEK / 2,
            end: end,
            cliff: cliffLength
        });
        // extending cliff period
        paramsList[3] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount / 2,
            start: start,
            end: end,
            cliff: cliffLength * 2
        });
        // extending start and decreasing cliff
        paramsList[4] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount * 3,
            start: start + WEEK / 2,
            end: end,
            cliff: cliffLength - WEEK / 2
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
        assertEq(govNFTLock.proposedSplits(from).timestamp, block.timestamp);
        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, splitLength);

        for (uint256 i = 0; i < splitLength; i++) {
            _checkProposedSplit(from, i, paramsList[i]);
        }
    }

    function test_CommitSplitOverridesPreviousCommit() public {
        (, , , , , uint256 cliffLength, uint256 start, uint256 end, , , ) = govNFTLock.locks(from);

        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 0);

        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit(from, address(recipient2), amount, start, end);
        vm.startPrank(address(recipient));
        IGovNFT.SplitParams memory params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: start,
            end: end,
            cliff: cliffLength
        });
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);

        _checkProposedSplit(from, 0, params);
        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 1);
        assertEq(govNFTLock.proposedSplits(from).timestamp, block.timestamp);

        params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount / 2,
            start: start + WEEK,
            end: end + WEEK,
            cliff: cliffLength + WEEK
        });
        paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);

        _checkProposedSplit(from, 0, params);
        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 1);
        assertEq(govNFTLock.proposedSplits(from).timestamp, block.timestamp);
    }

    function test_BatchCommitSplitOverridesPreviousCommit() public {
        (, , , , , uint256 cliffLength, uint256 start, uint256 end, , , ) = govNFTLock.locks(from);

        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 0);

        amount = TOKEN_1 * 1000;
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](5);
        // same timestamps as parent token
        // split timestamps can be the same as parent token because vesting has not started
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount,
            start: start,
            end: end,
            cliff: cliffLength
        });
        // extending end timestamp
        paramsList[1] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount * 2,
            start: start,
            end: end + 3 * WEEK,
            cliff: cliffLength
        });
        // extending start timestamp
        paramsList[2] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount + amount / 2,
            start: start + WEEK / 2,
            end: end,
            cliff: cliffLength
        });
        // extending cliff period
        paramsList[3] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount / 2,
            start: start,
            end: end,
            cliff: cliffLength * 2
        });
        // extending start and decreasing cliff
        paramsList[4] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount * 3,
            start: start + WEEK / 2,
            end: end,
            cliff: cliffLength - WEEK / 2
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
        assertEq(govNFTLock.proposedSplits(from).timestamp, block.timestamp);
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
            start: start + WEEK,
            end: end + WEEK,
            cliff: cliffLength + WEEK
        });
        // extending end timestamp
        paramsList[1] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount * 3,
            start: start + 1 days,
            end: end + 2 * WEEK,
            cliff: cliffLength - 1 days
        });
        // extending start timestamp
        paramsList[2] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount * 2,
            start: start + WEEK / 2,
            end: end,
            cliff: cliffLength
        });
        // extending cliff period
        paramsList[3] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount,
            start: start + WEEK / 2,
            end: end + WEEK,
            cliff: cliffLength - WEEK / 3
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
        assertEq(govNFTLock.proposedSplits(from).timestamp, block.timestamp);
        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, splitLength);

        for (uint256 i = 0; i < splitLength; i++) {
            _checkProposedSplit(from, i, paramsList[i]);
        }
    }

    function test_BatchCommitSplitDeletedAfterTransfer() public {
        (, , , , , uint256 cliffLength, uint256 start, uint256 end, , , ) = govNFTLock.locks(from);

        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 0);

        amount = TOKEN_1 * 1000;
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](5);
        // same timestamps as parent token
        // split timestamps can be the same as parent token because vesting has not started
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount,
            start: start,
            end: end,
            cliff: cliffLength
        });
        // extending end timestamp
        paramsList[1] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount * 2,
            start: start,
            end: end + 3 * WEEK,
            cliff: cliffLength
        });
        // extending start timestamp
        paramsList[2] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount + amount / 2,
            start: start + WEEK / 2,
            end: end,
            cliff: cliffLength
        });
        // extending cliff period
        paramsList[3] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount / 2,
            start: start,
            end: end,
            cliff: cliffLength * 2
        });
        // extending start and decreasing cliff
        paramsList[4] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount * 3,
            start: start + WEEK / 2,
            end: end,
            cliff: cliffLength - WEEK / 2
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
        assertEq(govNFTLock.proposedSplits(from).timestamp, block.timestamp);
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
        (, , , , , , uint256 start, uint256 end, , , address minter) = govNFTLock.locks(from);
        assertEq(minter, address(admin));

        address approvedUser = makeAddr("alice");
        assertEq(govNFTLock.balanceOf(approvedUser), 0);

        vm.prank(address(recipient));
        govNFTLock.approve(approvedUser, from);

        // can split after getting approval on nft
        vm.prank(approvedUser);
        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit(from, approvedUser, TOKEN_1, start, end);
        IGovNFT.SplitParams memory params = IGovNFT.SplitParams({
            beneficiary: approvedUser,
            amount: TOKEN_1,
            start: block.timestamp,
            end: block.timestamp + 3 * WEEK,
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
        emit IGovNFTTimelock.CommitSplit(from, approvedForAllUser, TOKEN_1, start, end);
        params = IGovNFT.SplitParams({
            beneficiary: approvedForAllUser,
            amount: TOKEN_1,
            start: block.timestamp,
            end: block.timestamp + 3 * WEEK,
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
            start: block.timestamp,
            end: block.timestamp + 3 * WEEK,
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
        govNFTLock.claim(tokenId, address(recipient), TOKEN_100K);
    }

    function test_RevertIf_CommitSplitIfZeroAmount() public {
        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.ZeroAmount.selector);
        IGovNFT.SplitParams memory params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: 0,
            start: block.timestamp,
            end: block.timestamp + 3 * WEEK,
            cliff: WEEK
        });
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);
    }

    function test_RevertIf_CommitSplitIfInvalidStart() public {
        (, , , , , uint256 cliff, uint256 start, uint256 end, , , ) = govNFTLock.locks(from);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.InvalidStart.selector);
        // new vesting cannot start before original vesting starts
        IGovNFT.SplitParams memory params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: start - 1,
            end: end,
            cliff: cliff
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
            start: start + 1,
            end: end,
            cliff: cliff
        });
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.InvalidStart.selector);
        params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: block.timestamp - 1,
            end: end,
            cliff: cliff
        });
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);
    }

    function test_RevertIf_CommitSplitWithInvalidEnd() public {
        (, , , , , uint256 cliff, , uint256 end, , , ) = govNFTLock.locks(from);

        vm.startPrank(address(recipient));
        IGovNFT.SplitParams memory params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: block.timestamp,
            end: end - 1,
            cliff: cliff
        });
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = params;

        // cannot split if proposed end is before `parentLock.end`
        vm.expectRevert(IGovNFT.InvalidEnd.selector);
        govNFTLock.commitSplit(from, paramsList);
    }

    function test_RevertIf_CommitSplitWithAmountTooBig() public {
        (uint256 totalLocked, , , , , uint256 cliff, , uint256 end, , , ) = govNFTLock.locks(from);

        vm.startPrank(address(recipient));
        // cannot propose split with amount higher than totallock
        IGovNFT.SplitParams memory params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: totalLocked + 1,
            start: block.timestamp,
            end: end,
            cliff: cliff
        });
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = params;

        vm.expectRevert(IGovNFT.AmountTooBig.selector);
        govNFTLock.commitSplit(from, paramsList);

        vm.warp(end); // warp to end of `parentLock` vesting period

        // cannot propose split if `parentLock` has finished vesting
        vm.expectRevert(IGovNFT.AmountTooBig.selector);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: TOKEN_1,
            start: block.timestamp,
            end: end + WEEK,
            cliff: cliff
        });
        govNFTLock.commitSplit(from, paramsList);
        vm.stopPrank();
    }

    function test_RevertIf_CommitSplitWithAmountTooBigMultipleSplits() public {
        (uint256 totalLocked, , , , , uint256 cliff, uint256 start, uint256 end, , , ) = govNFTLock.locks(from);

        vm.startPrank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](2);
        // sum of amounts should not be greater than totallocked
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: (totalLocked + TOKEN_1) / 2,
            start: block.timestamp,
            end: end,
            cliff: cliff
        });
        paramsList[1] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: (totalLocked + TOKEN_1) / 2,
            start: block.timestamp,
            end: end,
            cliff: cliff
        });

        vm.expectRevert(IGovNFT.AmountTooBig.selector);
        govNFTLock.commitSplit(from, paramsList);

        // skip some time to vest tokens
        skip((end - start) / 2);

        uint256 lockedAmount = govNFTLock.locked(from);

        // sum of amounts should not be greater than locked value
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: (lockedAmount + TOKEN_1) / 2,
            start: block.timestamp,
            end: end,
            cliff: cliff
        });
        paramsList[1] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: (lockedAmount + TOKEN_1) / 2,
            start: block.timestamp,
            end: end,
            cliff: cliff
        });

        vm.expectRevert(IGovNFT.AmountTooBig.selector);
        govNFTLock.commitSplit(from, paramsList);
        vm.stopPrank();
    }

    function test_RevertIf_CommitSplitIfEndBeforeOrEqualStart() public {
        (, , , , , , , uint256 end, , , ) = govNFTLock.locks(from);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.EndBeforeOrEqualStart.selector);
        IGovNFT.SplitParams memory params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: end + 1,
            end: end,
            cliff: 0
        });
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.EndBeforeOrEqualStart.selector);
        params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: end,
            end: end,
            cliff: 0
        });
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);
    }

    function test_RevertIf_CommitSplitIfInvalidCliff() public {
        (, , , , , uint256 cliff, uint256 start, uint256 end, , , ) = govNFTLock.locks(from);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.InvalidCliff.selector);
        IGovNFT.SplitParams memory params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: start,
            end: end,
            cliff: cliff - 1
        });
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.InvalidCliff.selector);
        params = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: end - cliff / 2,
            end: end,
            cliff: cliff
        });
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);
    }

    function test_RevertIf_CommitSplitZeroAddress() public {
        (, , , , , uint256 cliff, uint256 start, uint256 end, , , ) = govNFTLock.locks(from);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.ZeroAddress.selector);
        IGovNFT.SplitParams memory params = IGovNFT.SplitParams({
            beneficiary: address(0),
            amount: amount,
            start: start,
            end: end,
            cliff: cliff
        });
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = params;
        govNFTLock.commitSplit(from, paramsList);
    }
}
