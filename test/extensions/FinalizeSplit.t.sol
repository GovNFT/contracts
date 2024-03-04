// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract FinalizeSplitTest is BaseTest {
    uint256 public from;
    uint256 public amount;
    uint40 public timelockDelay = 1 days;
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
        from = govNFTLock.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            uint40(block.timestamp),
            uint40(block.timestamp) + WEEK * 3,
            WEEK
        );
        amount = TOKEN_10K * 4;
    }

    function test_FinalizeSplitBeforeStart() public {
        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.totalLocked, govNFT.locked(from)); // no tokens have been vested before splitting
        assertEq(lock.splitCount, 0);
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked);

        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start,
            end: lock.end,
            cliff: lock.cliffLength
        });
        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit({
            from: from,
            recipient: address(recipient2),
            splitAmount: amount,
            startTime: lock.start,
            endTime: lock.end
        });
        vm.startPrank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 1);
        assertEq(govNFTLock.proposedSplits(from).timestamp, uint40(block.timestamp));

        skip(timelockDelay);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: address(recipient2),
            splitAmount1: lock.totalLocked - amount,
            splitAmount2: amount,
            startTime: lock.start + timelockDelay,
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFTLock));
        emit IERC4906.MetadataUpdate(from);
        uint256 tokenId = govNFTLock.finalizeSplit(from)[0];
        vm.stopPrank();

        assertEq(govNFTLock.proposedSplits(from).timestamp, 0);
        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 0);

        // original NFT assertions
        // start timestamp and cliff account for `timelockDelay`, since tokens should not vest during this period
        _checkLockUpdates(
            from,
            lock.totalLocked - amount,
            lock.totalLocked,
            lock.cliffLength - timelockDelay,
            lock.start + timelockDelay,
            lock.end
        );
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), 0, 1);

        // split NFT assertions
        // start timestamps and cliffs remain the same as parent token
        _checkLockUpdates(
            tokenId,
            amount,
            amount,
            lock.cliffLength - timelockDelay,
            lock.start + timelockDelay,
            lock.end
        );
    }

    function test_FinalizeSplitClaimsBeforeStart() public {
        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.totalClaimed, 0);

        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start,
            end: lock.end,
            cliff: WEEK
        });
        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit({
            from: from,
            recipient: address(recipient2),
            splitAmount: amount,
            startTime: lock.start,
            endTime: lock.end
        });
        vm.startPrank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        skip(timelockDelay);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: address(recipient2),
            splitAmount1: lock.totalLocked - amount,
            splitAmount2: amount,
            startTime: lock.start + timelockDelay,
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFTLock));
        emit IERC4906.MetadataUpdate(from);
        uint256 tokenId = govNFTLock.finalizeSplit(from)[0];
        vm.stopPrank();

        _checkLockedUnclaimedSplit(from, lock.totalLocked - amount, 0, tokenId, amount, 0);

        vm.warp(govNFT.locks(tokenId).end);

        _checkLockedUnclaimedSplit(from, 0, lock.totalLocked - amount, tokenId, 0, amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        // assert claims
        assertEq(govNFT.locks(from).totalClaimed, 0);
        vm.prank(address(recipient));
        govNFT.claim(from, address(recipient), lock.totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), lock.totalLocked - amount);
        assertEq(govNFT.locks(from).totalClaimed, lock.totalLocked - amount);

        assertEq(govNFT.locks(tokenId).totalClaimed, 0);
        vm.prank(address(recipient2));
        govNFT.claim(tokenId, address(recipient2), lock.totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), amount);
        assertEq(govNFT.locks(tokenId).totalClaimed, amount);
    }

    function test_FinalizeSplitBeforeCliffEnd() public {
        skip(5 days); // skip somewhere before cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.totalLocked, govNFT.locked(from)); // still on cliff, no tokens vested
        assertEq(lock.splitCount, 0);
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked);

        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: WEEK - 5 days
        });

        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit({
            from: from,
            recipient: address(recipient2),
            splitAmount: amount,
            startTime: uint40(block.timestamp),
            endTime: lock.end
        });
        vm.startPrank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 1);
        assertEq(govNFTLock.proposedSplits(from).timestamp, uint40(block.timestamp));

        skip(timelockDelay);

        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: address(recipient2),
            splitAmount1: lock.totalLocked - amount,
            splitAmount2: amount,
            startTime: uint40(block.timestamp),
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFTLock));
        emit IERC4906.MetadataUpdate(from);
        uint256 tokenId = govNFTLock.finalizeSplit(from)[0];
        vm.stopPrank();

        assertEq(govNFTLock.proposedSplits(from).timestamp, 0);
        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 0);

        // original NFT assertions
        uint40 remainingCliff = (lock.start + lock.cliffLength) - uint40(block.timestamp);
        // since still on cliff and vesting has started, the split cliff length will be
        // the remaining cliff period and the new start will be the current timestamp
        _checkLockUpdates(
            from,
            lock.totalLocked - amount,
            lock.totalLocked,
            remainingCliff,
            uint40(block.timestamp),
            lock.end
        );
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), 0, 1);
        assertEq(remainingCliff, WEEK - (5 days + timelockDelay));

        // split NFT assertions
        _checkLockUpdates(tokenId, amount, amount, remainingCliff, uint40(block.timestamp), lock.end);
    }

    function test_FinalizeSplitClaimsBeforeCliffEnd() public {
        skip(5 days); // skip somewhere before cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.totalClaimed, 0);

        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: WEEK - 5 days
        });

        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit({
            from: from,
            recipient: address(recipient2),
            splitAmount: amount,
            startTime: uint40(block.timestamp),
            endTime: lock.end
        });
        vm.startPrank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        skip(timelockDelay);

        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: address(recipient2),
            splitAmount1: lock.totalLocked - amount,
            splitAmount2: amount,
            startTime: uint40(block.timestamp),
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFTLock));
        emit IERC4906.MetadataUpdate(from);
        uint256 tokenId = govNFTLock.finalizeSplit(from)[0];
        vm.stopPrank();

        _checkLockedUnclaimedSplit(from, lock.totalLocked - amount, 0, tokenId, amount, 0);

        vm.warp(govNFT.locks(tokenId).end);

        _checkLockedUnclaimedSplit(from, 0, lock.totalLocked - amount, tokenId, 0, amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        // assert claims
        assertEq(govNFT.locks(from).totalClaimed, 0);
        vm.prank(address(recipient));
        govNFT.claim(from, address(recipient), lock.totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), lock.totalLocked - amount);
        assertEq(govNFT.locks(from).totalClaimed, lock.totalLocked - amount);

        assertEq(govNFT.locks(tokenId).totalClaimed, 0);
        vm.prank(address(recipient2));
        govNFT.claim(tokenId, address(recipient2), lock.totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), amount);
        assertEq(govNFT.locks(tokenId).totalClaimed, amount);
    }

    function test_FinalizeSplitAfterCliffEnd() public {
        skip(WEEK + 2 days); // skip somewhere after cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.splitCount, 0);
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked);

        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: 0
        });
        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit({
            from: from,
            recipient: address(recipient2),
            splitAmount: amount,
            startTime: uint40(block.timestamp),
            endTime: lock.end
        });
        vm.startPrank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 1);
        assertEq(govNFTLock.proposedSplits(from).timestamp, uint40(block.timestamp));

        skip(timelockDelay);

        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: address(recipient2),
            splitAmount1: lockedBeforeSplit - amount,
            splitAmount2: amount,
            startTime: uint40(block.timestamp),
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        uint256 tokenId = govNFTLock.finalizeSplit(from)[0];
        vm.stopPrank();

        assertEq(govNFTLock.proposedSplits(from).timestamp, 0);
        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 0);

        assertEq(lock.totalLocked, govNFT.locked(from) + govNFT.locked(tokenId) + originalUnclaimed);

        // original NFT assertions
        // no cliff since vesting has already started
        _checkLockUpdates(from, lockedBeforeSplit - amount, lock.totalLocked, 0, uint40(block.timestamp), lock.end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), originalUnclaimed, 1);
        assertEq(govNFT.locked(from), govNFT.locks(from).totalLocked);

        // split NFT assertions
        // no cliff since vesting has already started
        _checkLockUpdates(tokenId, amount, amount, 0, uint40(block.timestamp), lock.end);

        assertEq(govNFT.locked(tokenId), govNFT.locks(tokenId).totalLocked);
    }

    function test_FinalizeSplitAfterCliffEndAndClaim() public {
        skip(WEEK + 2 days); // skip somewhere after cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.splitCount, 0);

        vm.prank(address(recipient));
        govNFT.claim(from, address(recipient), lock.totalLocked);
        uint256 totalClaimed = govNFT.locks(from).totalClaimed;

        skip(2 days); // skip somewhere before vesting ends to vest more rewards
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked - totalClaimed);

        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: 0
        });
        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit({
            from: from,
            recipient: address(recipient2),
            splitAmount: amount,
            startTime: uint40(block.timestamp),
            endTime: lock.end
        });
        vm.startPrank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 1);
        assertEq(govNFTLock.proposedSplits(from).timestamp, uint40(block.timestamp));

        skip(timelockDelay);

        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: address(recipient2),
            splitAmount1: lockedBeforeSplit - amount,
            splitAmount2: amount,
            startTime: uint40(block.timestamp),
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        uint256 tokenId = govNFTLock.finalizeSplit(from)[0];
        vm.stopPrank();

        assertEq(govNFTLock.proposedSplits(from).timestamp, 0);
        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 0);

        assertEq(lock.totalLocked, govNFT.locked(from) + govNFT.locked(tokenId) + originalUnclaimed + totalClaimed);

        // original NFT assertions
        // no cliff since vesting has already started
        _checkLockUpdates(from, lockedBeforeSplit - amount, lock.totalLocked, 0, uint40(block.timestamp), lock.end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), originalUnclaimed, 1);
        assertEq(govNFT.locked(from), govNFT.locks(from).totalLocked);

        // split NFT assertions
        // no cliff since vesting has already started
        _checkLockUpdates(tokenId, amount, amount, 0, uint40(block.timestamp), lock.end);
        assertEq(govNFT.locked(tokenId), govNFT.locks(tokenId).totalLocked);
    }

    function testFuzz_FinalizeSplitAfterCliffEnd(uint32 delay) public {
        IGovNFT.Lock memory lock = govNFT.locks(from);
        delay = uint32(bound(delay, 0, lock.end - (lock.start + lock.cliffLength) - 2 days));

        skip(lock.cliffLength); // skip cliff, so that tokens start vesting right away
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.splitCount, 0);
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked);

        // using a small split amount to avoid amounttoobig revert
        uint256 splitAmount = 10 * TOKEN_1;
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: splitAmount,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: 0
        });
        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit({
            from: from,
            recipient: address(recipient2),
            splitAmount: splitAmount,
            startTime: uint40(block.timestamp),
            endTime: lock.end
        });
        vm.startPrank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 1);
        assertEq(govNFTLock.proposedSplits(from).timestamp, uint40(block.timestamp));

        skip(timelockDelay + delay);

        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: address(recipient2),
            splitAmount1: lockedBeforeSplit - splitAmount,
            splitAmount2: splitAmount,
            startTime: uint40(block.timestamp),
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        uint256 tokenId = govNFTLock.finalizeSplit(from)[0];
        vm.stopPrank();

        assertEq(govNFTLock.proposedSplits(from).timestamp, 0);
        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 0);

        assertEq(lock.totalLocked, govNFT.locked(from) + govNFT.locked(tokenId) + originalUnclaimed);

        // original NFT assertions
        // no cliff since vesting has already started
        _checkLockUpdates(
            from,
            lockedBeforeSplit - splitAmount,
            lock.totalLocked,
            0,
            uint40(block.timestamp),
            lock.end
        );
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), originalUnclaimed, 1);
        assertEq(govNFT.locked(from), govNFT.locks(from).totalLocked);

        // split NFT assertions
        // no cliff since vesting has already started
        _checkLockUpdates(tokenId, splitAmount, splitAmount, 0, uint40(block.timestamp), lock.end);

        assertEq(govNFT.locked(tokenId), govNFT.locks(tokenId).totalLocked);
    }

    function test_FinalizeSplitClaimsWithUnclaimedRewardsAfterCliffEnd() public {
        skip(WEEK + 2 days); // skip somewhere after cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.totalClaimed, 0);

        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: 0
        });
        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit({
            from: from,
            recipient: address(recipient2),
            splitAmount: amount,
            startTime: uint40(block.timestamp),
            endTime: lock.end
        });
        vm.startPrank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        skip(timelockDelay);

        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: address(recipient2),
            splitAmount1: lockedBeforeSplit - amount,
            splitAmount2: amount,
            startTime: uint40(block.timestamp),
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        uint256 tokenId = govNFTLock.finalizeSplit(from)[0];
        vm.stopPrank();

        // previous unclaimed tokens are stored
        assertEq(govNFT.locks(from).unclaimedBeforeSplit, originalUnclaimed);
        assertEq(govNFT.locks(from).totalClaimed, 0);

        assertEq(govNFT.locks(tokenId).unclaimedBeforeSplit, 0);
        assertEq(govNFT.locks(tokenId).totalClaimed, 0);

        // the only amount claimable is the originalUnclaimed
        assertEq(lock.totalLocked, lockedBeforeSplit + originalUnclaimed);

        _checkLockedUnclaimedSplit(from, lockedBeforeSplit - amount, originalUnclaimed, tokenId, amount, 0);

        vm.warp(govNFT.locks(tokenId).end);

        _checkLockedUnclaimedSplit(from, 0, originalUnclaimed + lockedBeforeSplit - amount, tokenId, 0, amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        // assert claims
        vm.prank(address(recipient));
        govNFT.claim(from, address(recipient), lock.totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), originalUnclaimed + lockedBeforeSplit - amount);
        assertEq(govNFT.locks(from).totalClaimed, lockedBeforeSplit - amount); //unclaimed before split not included

        vm.prank(address(recipient2));
        govNFT.claim(tokenId, address(recipient2), lock.totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), amount);
        assertEq(govNFT.locks(tokenId).totalClaimed, amount);
    }

    function testFuzz_FinalizeSplitClaimsWithUnclaimedRewardsAfterCliffEnd(uint32 delay) public {
        IGovNFT.Lock memory lock = govNFT.locks(from);
        delay = uint32(bound(delay, 0, lock.end - (lock.start + lock.cliffLength) - 2 days));

        skip(lock.cliffLength); // skip cliff, so that tokens start vesting right away

        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.totalClaimed, 0);

        // using a small split amount to avoid amounttoobig revert
        uint256 splitAmount = 10 * TOKEN_1;
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: splitAmount,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: 0
        });
        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit({
            from: from,
            recipient: address(recipient2),
            splitAmount: splitAmount,
            startTime: uint40(block.timestamp),
            endTime: lock.end
        });
        vm.startPrank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        skip(timelockDelay + delay);

        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: address(recipient2),
            splitAmount1: lockedBeforeSplit - splitAmount,
            splitAmount2: splitAmount,
            startTime: uint40(block.timestamp),
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        uint256 tokenId = govNFTLock.finalizeSplit(from)[0];
        vm.stopPrank();

        // previous unclaimed tokens are stored
        assertEq(govNFT.locks(from).unclaimedBeforeSplit, originalUnclaimed);
        assertEq(govNFT.locks(from).totalClaimed, 0);

        assertEq(govNFT.locks(tokenId).unclaimedBeforeSplit, 0);
        assertEq(govNFT.locks(tokenId).totalClaimed, 0);

        // the only amount claimable is the originalUnclaimed
        assertEq(lock.totalLocked, lockedBeforeSplit + originalUnclaimed);

        _checkLockedUnclaimedSplit(from, lockedBeforeSplit - splitAmount, originalUnclaimed, tokenId, splitAmount, 0);

        vm.warp(govNFT.locks(tokenId).end);

        _checkLockedUnclaimedSplit(
            from,
            0,
            originalUnclaimed + lockedBeforeSplit - splitAmount,
            tokenId,
            0,
            splitAmount
        );
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        // assert claims
        vm.prank(address(recipient));
        govNFT.claim(from, address(recipient), lock.totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), originalUnclaimed + lockedBeforeSplit - splitAmount);

        assertEq(govNFT.locks(from).totalClaimed, lockedBeforeSplit - splitAmount); //unclaimed before split not included

        vm.prank(address(recipient2));
        govNFT.claim(tokenId, address(recipient2), lock.totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), splitAmount);
        assertEq(govNFT.locks(tokenId).totalClaimed, splitAmount);
    }

    function test_RevertIf_FinalizeSplitAmountTooBig() public {
        IGovNFT.Lock memory lock = govNFT.locks(from);

        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);

        // skip some time to vest tokens
        skip((lock.end - lock.start) / 2);

        // the max amount that can be split in this timestamp is `lockedAmount`
        uint256 lockedAmount = govNFTLock.locked(from);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: lockedAmount,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: lock.cliffLength
        });
        vm.startPrank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        skip(timelockDelay);

        // this split should fail now since there are less locked tokens than before,
        // because the timelock period has passed and tokens have vested in `parentLock` during this time
        assertLt(govNFTLock.locked(from), lockedAmount);
        vm.expectRevert(IGovNFT.AmountTooBig.selector);
        govNFTLock.finalizeSplit(from);
    }

    function test_RevertIf_FinalizeSplitAmountTooBigMultipleSplits() public {
        IGovNFT.Lock memory lock = govNFT.locks(from);

        // skip some time to vest tokens
        skip((lock.end - lock.start) / 2);

        uint256 lockedAmount = govNFTLock.locked(from);

        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](2);
        // sum of amounts should not be greater than locked value at the time of finalization
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: lockedAmount / 2,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: lock.cliffLength
        });
        paramsList[1] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: lockedAmount / 2,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: lock.cliffLength
        });

        vm.startPrank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        skip(timelockDelay);

        // this transfer should fail now since there are less locked tokens than before,
        // because the timelock period has passed and tokens have vested in the `parentLock` during this time
        assertLt(govNFTLock.locked(from), lockedAmount);
        vm.expectRevert(IGovNFT.AmountTooBig.selector);
        govNFTLock.finalizeSplit(from);
    }

    function test_RevertIf_FinalizeSplitAfterTransfer() public {
        IGovNFT.Lock memory lock = govNFT.locks(from);

        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start,
            end: lock.end,
            cliff: lock.cliffLength
        });
        vm.startPrank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 1);
        assertEq(govNFTLock.proposedSplits(from).timestamp, uint40(block.timestamp));

        skip(timelockDelay);

        govNFTLock.transferFrom(address(recipient), address(recipient2), from);

        assertEq(govNFTLock.proposedSplits(from).timestamp, 0);
        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 0);

        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(recipient), from)
        );
        govNFTLock.finalizeSplit(from);
        vm.stopPrank();
    }

    function test_RevertIf_FinalizeSplitAfterParentLockEnd() public {
        IGovNFT.Lock memory lock = govNFT.locks(from);

        vm.warp(lock.end - timelockDelay); // when timelockDelay is passed, parentLock will have stopped vesting

        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.splitCount, 0);
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked);

        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: TOKEN_1 * 1000,
            start: uint40(block.timestamp),
            end: lock.end + WEEK,
            cliff: 0
        });
        vm.startPrank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 1);
        assertEq(govNFTLock.proposedSplits(from).timestamp, uint40(block.timestamp));

        // this skip reaches `parentLock.end`, vesting all of the parenLock's tokens
        skip(timelockDelay);

        // `from` has 0 tokens locked, cannot perform any split
        vm.expectRevert(IGovNFT.AmountTooBig.selector);
        govNFTLock.finalizeSplit(from);
    }
}
