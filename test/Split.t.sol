// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract SplitTest is BaseTest {
    uint256 public from;
    uint256 public amount;

    function _setUp() public override {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        from = govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 3,
            WEEK
        );
        amount = TOKEN_10K * 4;
    }

    function test_SplitBeforeStart() public {
        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.totalLocked, govNFT.locked(from)); // no tokens have been vested before splitting
        assertEq(lock.splitCount, 0);
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: address(recipient2),
            splitAmount1: lock.totalLocked - amount,
            splitAmount2: amount,
            startTime: lock.start,
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start,
            end: lock.end,
            cliff: lock.cliffLength
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];

        // original NFT assertions
        // start timestamps and cliffs remain the same as parent token, since vesting has not started
        _checkLockUpdates(from, lock.totalLocked - amount, lock.totalLocked, lock.cliffLength, lock.start, lock.end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), 0, 1);

        // split NFT assertions
        // start timestamps and cliffs remain the same as parent token
        _checkLockUpdates(tokenId, amount, amount, lock.cliffLength, lock.start, lock.end);
    }

    function test_SplitClaimsBeforeStart() public {
        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.totalClaimed, 0);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: address(recipient2),
            splitAmount1: lock.totalLocked - amount,
            splitAmount2: amount,
            startTime: lock.start,
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start,
            end: lock.end,
            cliff: WEEK
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];

        _checkLockedUnclaimedSplit(from, lock.totalLocked - amount, 0, tokenId, amount, 0);

        vm.warp(govNFT.locks(tokenId).end); // Warp to end of Split Lock vesting

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

    function test_SplitBeforeCliffEnd() public {
        skip(5 days); // skip somewhere before cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.totalLocked, govNFT.locked(from)); // still on cliff, no tokens vested
        assertEq(lock.splitCount, 0);
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: address(recipient2),
            splitAmount1: lock.totalLocked - amount,
            splitAmount2: amount,
            startTime: block.timestamp,
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: block.timestamp,
            end: lock.end,
            cliff: WEEK - 5 days
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];

        // original NFT assertions
        uint256 remainingCliff = (lock.start + lock.cliffLength) - block.timestamp;
        // since still on cliff and vesting has started, the split cliff length will be
        // the remaining cliff period and the new start will be the current timestamp
        _checkLockUpdates(from, lock.totalLocked - amount, lock.totalLocked, remainingCliff, block.timestamp, lock.end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), 0, 1);
        assertEq(remainingCliff, WEEK - 5 days);

        // split NFT assertions
        _checkLockUpdates(tokenId, amount, amount, remainingCliff, block.timestamp, lock.end);
    }

    function test_SplitClaimsBeforeCliffEnd() public {
        skip(5 days); // skip somewhere before cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.totalClaimed, 0);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: address(recipient2),
            splitAmount1: lock.totalLocked - amount,
            splitAmount2: amount,
            startTime: block.timestamp,
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: block.timestamp,
            end: lock.end,
            cliff: WEEK - 5 days
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];

        _checkLockedUnclaimedSplit(from, lock.totalLocked - amount, 0, tokenId, amount, 0);

        vm.warp(govNFT.locks(tokenId).end); // Warp to end of Split Lock

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

    function test_SplitAfterCliffEnd() public {
        skip(WEEK + 2 days); // skip somewhere after cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.splitCount, 0);
        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: address(recipient2),
            splitAmount1: lockedBeforeSplit - amount,
            splitAmount2: amount,
            startTime: block.timestamp,
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: block.timestamp,
            end: lock.end,
            cliff: 0
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];

        assertEq(lock.totalLocked, govNFT.locked(from) + govNFT.locked(tokenId) + originalUnclaimed);

        // original NFT assertions
        uint256 totalLockedSplit = govNFT.locks(from).totalLocked;

        // no cliff since vesting has already started
        _checkLockUpdates(from, lockedBeforeSplit - amount, lock.totalLocked, 0, block.timestamp, lock.end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), originalUnclaimed, 1);
        assertEq(govNFT.locked(from), totalLockedSplit);

        // split NFT assertions
        totalLockedSplit = govNFT.locks(tokenId).totalLocked;

        // no cliff since vesting has already started
        _checkLockUpdates(tokenId, amount, amount, 0, block.timestamp, lock.end);

        assertEq(govNFT.locked(tokenId), totalLockedSplit);
    }

    function test_SplitAfterCliffEndAndClaim() public {
        skip(WEEK + 2 days); // skip somewhere after cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.splitCount, 0);

        vm.prank(address(recipient));
        govNFT.claim(from, address(recipient), lock.totalLocked);
        lock = govNFT.locks(from);

        skip(2 days); // skip somewhere before vesting ends to vest more rewards
        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked - lock.totalClaimed);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: address(recipient2),
            splitAmount1: lockedBeforeSplit - amount,
            splitAmount2: amount,
            startTime: block.timestamp,
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: block.timestamp,
            end: lock.end,
            cliff: 0
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];

        assertEq(
            lock.totalLocked,
            govNFT.locked(from) + govNFT.locked(tokenId) + originalUnclaimed + lock.totalClaimed
        );

        // original NFT assertions
        uint256 totalLockedSplit = govNFT.locks(from).totalLocked;

        // no cliff since vesting has already started
        _checkLockUpdates(from, lockedBeforeSplit - amount, lock.totalLocked, 0, block.timestamp, lock.end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), originalUnclaimed, 1);
        assertEq(govNFT.locked(from), totalLockedSplit);

        // split NFT assertions
        totalLockedSplit = govNFT.locks(tokenId).totalLocked;

        // no cliff since vesting has already started
        _checkLockUpdates(tokenId, amount, amount, 0, block.timestamp, lock.end);
        assertEq(govNFT.locked(tokenId), totalLockedSplit);
    }

    function test_SplitClaimsWithUnclaimedRewardsAfterCliffEnd() public {
        skip(WEEK + 2 days); // skip somewhere after cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.totalClaimed, 0);
        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: address(recipient2),
            splitAmount1: lockedBeforeSplit - amount,
            splitAmount2: amount,
            startTime: block.timestamp,
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: block.timestamp,
            end: lock.end,
            cliff: WEEK
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];

        // previous unclaimed tokens are stored
        assertEq(govNFT.locks(from).unclaimedBeforeSplit, originalUnclaimed);
        assertEq(govNFT.locks(from).totalClaimed, 0);

        assertEq(govNFT.locks(tokenId).unclaimedBeforeSplit, 0);
        assertEq(govNFT.locks(tokenId).totalClaimed, 0);

        // the only amount claimable is the originalUnclaimed
        assertEq(lock.totalLocked, lockedBeforeSplit + originalUnclaimed);

        _checkLockedUnclaimedSplit(from, lockedBeforeSplit - amount, originalUnclaimed, tokenId, amount, 0);

        vm.warp(govNFT.locks(tokenId).end); // Warp to end of Split Lock vesting

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

    function test_SplitClaimsAtSplitTimestampWithUnclaimedRewardsAfterCliffEnd() public {
        skip(WEEK + 2 days); // skip somewhere after cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.totalClaimed, 0);
        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: address(recipient2),
            splitAmount1: lockedBeforeSplit - amount,
            splitAmount2: amount,
            startTime: block.timestamp,
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: block.timestamp,
            end: lock.end,
            cliff: WEEK
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];

        // previous unclaimed tokens are stored
        assertEq(govNFT.locks(from).unclaimedBeforeSplit, originalUnclaimed);
        assertEq(govNFT.locks(from).totalClaimed, 0);

        assertEq(govNFT.locks(tokenId).unclaimedBeforeSplit, 0);
        assertEq(govNFT.locks(tokenId).totalClaimed, 0);

        // the only amount claimable is the originalUnclaimed
        assertEq(lock.totalLocked, lockedBeforeSplit + originalUnclaimed);

        _checkLockedUnclaimedSplit(from, lockedBeforeSplit - amount, originalUnclaimed, tokenId, amount, 0);

        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        // assert claims
        vm.prank(address(recipient));
        govNFT.claim(from, address(recipient), lock.totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), originalUnclaimed);
        assertEq(govNFT.locks(from).totalClaimed, 0); // unclaimed before split not included

        // nothing to claim on split token in split timestamp
        vm.prank(address(recipient2));
        govNFT.claim(tokenId, address(recipient2), lock.totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(govNFT.locks(tokenId).totalClaimed, 0);
    }

    function test_SplitClaimsWithClaimedRewardsAfterCliffEnd() public {
        skip(WEEK + 2 days); // skip somewhere after cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.totalClaimed, 0);
        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);

        vm.prank(address(recipient));
        govNFT.claim(from, address(recipient), lock.totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), originalUnclaimed);
        assertEq(govNFT.locks(from).totalClaimed, originalUnclaimed);
        assertEq(govNFT.unclaimed(from), 0);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: address(recipient2),
            splitAmount1: lockedBeforeSplit - amount,
            splitAmount2: amount,
            startTime: block.timestamp,
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: block.timestamp,
            end: lock.end,
            cliff: WEEK
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];

        // previous totalClaimed was reset and no rewards were left unclaimed
        assertEq(govNFT.locks(from).totalClaimed, 0);
        assertEq(govNFT.locks(from).unclaimedBeforeSplit, 0);

        assertEq(govNFT.locks(tokenId).totalClaimed, 0);
        assertEq(govNFT.locks(tokenId).unclaimedBeforeSplit, 0);

        // the only amount claimable is the originalUnclaimed
        assertEq(lock.totalLocked, lockedBeforeSplit + originalUnclaimed);

        _checkLockedUnclaimedSplit(from, lockedBeforeSplit - amount, 0, tokenId, amount, 0);

        vm.warp(govNFT.locks(tokenId).end); // Warp to end of Split Lock vesting

        _checkLockedUnclaimedSplit(from, 0, lockedBeforeSplit - amount, tokenId, 0, amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), originalUnclaimed);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);

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

    function test_RecursiveSplitBeforeStart() public {
        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.totalLocked, govNFT.locked(from)); // no tokens have been vested before splitting
        assertEq(lock.splitCount, 0);
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: address(recipient),
            splitAmount1: lock.totalLocked - amount,
            splitAmount2: amount,
            startTime: lock.start,
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount,
            start: block.timestamp,
            end: block.timestamp + 3 * WEEK,
            cliff: WEEK
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];

        // parent NFT assertions
        // start timestamps and cliffs remain the same as parent token, since vesting has not started
        _checkLockUpdates(from, lock.totalLocked - amount, lock.totalLocked, lock.cliffLength, lock.start, lock.end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient), 0, 1);

        // split NFT assertions
        // start timestamps and cliffs remain the same as parent token
        _checkLockUpdates(tokenId, amount, amount, lock.cliffLength, lock.start, lock.end);

        // second split assertions
        lock = govNFT.locks(tokenId);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.totalLocked, govNFT.locked(tokenId)); // no tokens have been vested before splitting
        assertEq(lock.splitCount, 0);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: tokenId,
            tokenId: tokenId + 1,
            recipient: address(recipient2),
            splitAmount1: lock.totalLocked - amount / 2,
            splitAmount2: amount / 2,
            startTime: lock.start,
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(tokenId);
        vm.prank(address(recipient));
        paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount / 2,
            start: block.timestamp,
            end: block.timestamp + 3 * WEEK,
            cliff: WEEK
        });
        uint256 tokenId2 = govNFT.split(tokenId, paramsList)[0];

        // parent NFT assertions
        // start timestamps and cliffs remain the same as parent token, since vesting has not started
        _checkLockUpdates(
            tokenId,
            lock.totalLocked - amount / 2,
            lock.totalLocked,
            lock.cliffLength,
            lock.start,
            lock.end
        );
        _checkSplitInfo(tokenId, tokenId2, address(recipient), address(recipient2), 0, 1);

        // split NFT assertions
        // start timestamps and cliffs remain the same as parent token
        _checkLockUpdates(tokenId2, amount / 2, amount / 2, lock.cliffLength, lock.start, lock.end);
    }

    function test_RecursiveSplitBeforeCliffEnd() public {
        skip(2 days); // skip somewhere before cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.totalLocked, govNFT.locked(from)); // still on cliff, no tokens vested
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.splitCount, 0);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: address(recipient),
            splitAmount1: lock.totalLocked - amount,
            splitAmount2: amount,
            startTime: block.timestamp,
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount,
            start: block.timestamp,
            end: lock.end,
            cliff: WEEK - 2 days
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];

        // original NFT assertions
        uint256 remainingCliff = (lock.start + lock.cliffLength) - block.timestamp;
        // since still on cliff and vesting has started, the split cliff length will be
        // the remaining cliff period and the new start will be the current timestamp
        _checkLockUpdates(from, lock.totalLocked - amount, lock.totalLocked, remainingCliff, block.timestamp, lock.end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient), 0, 1);
        assertEq(remainingCliff, WEEK - 2 days);

        // split NFT assertions
        _checkLockUpdates(tokenId, amount, amount, remainingCliff, block.timestamp, lock.end);

        // second split assertions
        skip(2 days); // skip somewhere before cliff ends

        lock = govNFT.locks(tokenId);

        assertEq(lock.totalLocked, govNFT.locked(tokenId)); // still on cliff, no tokens vested
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.splitCount, 0);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: tokenId,
            tokenId: tokenId + 1,
            recipient: address(recipient2),
            splitAmount1: lock.totalLocked - amount / 2,
            splitAmount2: amount / 2,
            startTime: block.timestamp,
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(tokenId);
        vm.prank(address(recipient));
        paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount / 2,
            start: block.timestamp,
            end: lock.end,
            cliff: WEEK - 4 days
        });
        uint256 tokenId2 = govNFT.split(tokenId, paramsList)[0];

        // original NFT assertions
        remainingCliff = (lock.start + lock.cliffLength) - block.timestamp;
        // since still on cliff and vesting has started, the split cliff length will be
        // the remaining cliff period and the new start will be the current timestamp
        _checkLockUpdates(
            tokenId,
            lock.totalLocked - amount / 2,
            lock.totalLocked,
            remainingCliff,
            block.timestamp,
            lock.end
        );
        _checkSplitInfo(tokenId, tokenId2, address(recipient), address(recipient2), 0, 1);
        assertEq(remainingCliff, WEEK - 4 days);

        // split NFT assertions
        _checkLockUpdates(tokenId2, amount / 2, amount / 2, remainingCliff, block.timestamp, lock.end);
    }

    function test_RecursiveSplitAfterCliffEnd() public {
        skip(WEEK + 2 days); // skip somewhere after cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.splitCount, 0);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: address(recipient),
            splitAmount1: lockedBeforeSplit - amount,
            splitAmount2: amount,
            startTime: block.timestamp,
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount,
            start: block.timestamp,
            end: lock.end,
            cliff: 0
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];

        assertEq(lock.totalLocked, govNFT.locked(from) + govNFT.locked(tokenId) + originalUnclaimed);

        // original NFT assertions
        // no cliff since vesting has already started
        _checkLockUpdates(from, lockedBeforeSplit - amount, lock.totalLocked, 0, block.timestamp, lock.end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient), originalUnclaimed, 1);
        assertEq(govNFT.locked(from), govNFT.locks(from).totalLocked);

        // split NFT assertions
        // no cliff since vesting has already started
        _checkLockUpdates(tokenId, amount, amount, 0, block.timestamp, lock.end);
        assertEq(govNFT.locked(tokenId), govNFT.locks(tokenId).totalLocked);

        // second split checks
        skip(2 days);

        lock = govNFT.locks(tokenId);

        lockedBeforeSplit = govNFT.locked(tokenId);
        originalUnclaimed = govNFT.unclaimed(tokenId);
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.splitCount, 0);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: tokenId,
            tokenId: tokenId + 1,
            recipient: address(recipient2),
            splitAmount1: lockedBeforeSplit - amount / 2,
            splitAmount2: amount / 2,
            startTime: block.timestamp,
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(tokenId);
        vm.prank(address(recipient));
        paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount / 2,
            start: block.timestamp,
            end: lock.end,
            cliff: 0
        });
        uint256 tokenId2 = govNFT.split(tokenId, paramsList)[0];

        assertEq(lock.totalLocked, govNFT.locked(tokenId) + govNFT.locked(tokenId2) + originalUnclaimed);

        // original NFT assertions
        // no cliff since vesting has already started
        _checkLockUpdates(tokenId, lockedBeforeSplit - amount / 2, lock.totalLocked, 0, block.timestamp, lock.end);
        _checkSplitInfo(tokenId, tokenId2, address(recipient), address(recipient2), originalUnclaimed, 1);
        assertEq(govNFT.locked(tokenId), govNFT.locks(tokenId).totalLocked);

        // split NFT assertions
        // no cliff since vesting has already started
        _checkLockUpdates(tokenId2, amount / 2, amount / 2, 0, block.timestamp, lock.end);
        assertEq(govNFT.locked(tokenId2), govNFT.locks(tokenId2).totalLocked);
    }

    function test_SplitPermissions() public {
        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.minter, address(admin));

        address approvedUser = makeAddr("alice");
        assertEq(govNFT.balanceOf(approvedUser), 0);

        vm.prank(address(recipient));
        govNFT.approve(approvedUser, from);

        // can split after getting approval on nft
        vm.prank(approvedUser);
        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: approvedUser,
            splitAmount1: lock.totalLocked - TOKEN_1,
            splitAmount2: TOKEN_1,
            startTime: lock.start,
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: approvedUser,
            amount: TOKEN_1,
            start: block.timestamp,
            end: block.timestamp + 3 * WEEK,
            cliff: WEEK
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];

        assertEq(govNFT.ownerOf(tokenId), approvedUser);
        assertEq(govNFT.balanceOf(approvedUser), 1);
        // split updates minter in child lock
        assertEq(govNFT.locks(tokenId).minter, approvedUser);

        address approvedForAllUser = makeAddr("bob");
        assertEq(govNFT.balanceOf(approvedForAllUser), 0);

        vm.prank(address(recipient));
        govNFT.setApprovalForAll(approvedForAllUser, true);

        // can split after getting approval for all nfts
        vm.prank(approvedForAllUser);
        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: from,
            tokenId: tokenId + 1,
            recipient: approvedForAllUser,
            splitAmount1: lock.totalLocked - TOKEN_1 * 2,
            splitAmount2: TOKEN_1,
            startTime: lock.start,
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: approvedForAllUser,
            amount: TOKEN_1,
            start: block.timestamp,
            end: block.timestamp + 3 * WEEK,
            cliff: WEEK
        });
        uint256 tokenId2 = govNFT.split(from, paramsList)[0];

        assertEq(govNFT.ownerOf(tokenId2), approvedForAllUser);
        assertEq(govNFT.balanceOf(approvedForAllUser), 1);
        // split updates minter in child lock
        assertEq(govNFT.locks(tokenId2).minter, approvedForAllUser);
    }

    function test_RevertIf_SplitIfNotRecipientOrApproved() public {
        address testUser = makeAddr("alice");

        vm.prank(testUser);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, testUser, from));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: TOKEN_1,
            start: block.timestamp,
            end: block.timestamp + 3 * WEEK,
            cliff: WEEK
        });
        govNFT.split(from, paramsList);

        vm.prank(address(admin));
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(admin), from)
        );
        paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: TOKEN_1,
            start: block.timestamp,
            end: block.timestamp + 3 * WEEK,
            cliff: WEEK
        });
        govNFT.split(from, paramsList);
    }

    function test_RevertIf_SplitNonExistentToken() public {
        uint256 tokenId = from + 2;
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: TOKEN_1,
            start: block.timestamp,
            end: block.timestamp + 3 * WEEK,
            cliff: WEEK
        });
        govNFT.split(tokenId, paramsList);
    }

    function test_RevertIf_SplitZeroAmount() public {
        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.ZeroAmount.selector);
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: 0,
            start: block.timestamp,
            end: block.timestamp + 3 * WEEK,
            cliff: WEEK
        });
        govNFT.split(from, paramsList);
    }

    function test_RevertIf_SplitWhenAmountTooBig() public {
        skip(WEEK + 1);

        IGovNFT.Lock memory lock = govNFT.locks(from);
        uint256 lockedBalance = govNFT.locked(from);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.AmountTooBig.selector);
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: lockedBalance + 1,
            start: block.timestamp,
            end: lock.end,
            cliff: 0
        });
        govNFT.split(from, paramsList);

        skip(WEEK + 1 days);

        lockedBalance = govNFT.locked(from);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.AmountTooBig.selector);
        paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: lockedBalance + 1,
            start: block.timestamp,
            end: block.timestamp + WEEK * 3,
            cliff: WEEK
        });
        govNFT.split(from, paramsList);
    }

    function test_RevertIf_SplitWhenVestingIsFinished() public {
        skip(WEEK * 3);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.AmountTooBig.selector);
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: block.timestamp,
            end: block.timestamp + WEEK * 3,
            cliff: WEEK
        });
        govNFT.split(from, paramsList);
    }

    function test_SplitTokensByIndex(uint8 splits) public {
        vm.startPrank(address(recipient));
        uint256[] memory tokens = new uint256[](splits);
        uint256 tokenId;
        // create multiple splits
        for (uint256 i = 0; i < splits; i++) {
            assertEq(govNFT.balanceOf(address(recipient2)), i);
            assertEq(govNFT.locks(from).splitCount, i);

            IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
            paramsList[0] = IGovNFT.SplitParams({
                beneficiary: address(recipient2),
                amount: TOKEN_1,
                start: block.timestamp,
                end: block.timestamp + WEEK * 3,
                cliff: WEEK
            });
            tokenId = govNFT.split(from, paramsList)[0];
            tokens[i] = tokenId;

            assertEq(govNFT.balanceOf(address(recipient2)), i + 1);
            assertEq(govNFT.locks(from).splitCount, i + 1);
        }
        // assert all splits are in list
        uint256 splitCount = govNFT.locks(from).splitCount;
        for (uint256 i = 0; i < splitCount; i++) {
            assertEq(govNFT.splitTokensByIndex(from, i), tokens[i]);
        }
    }

    function test_SplitToUpdatesTimestamps() public {
        IGovNFT.Lock memory lock = govNFT.locks(from);

        vm.prank(address(recipient));
        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: address(recipient2),
            splitAmount1: lock.totalLocked - amount,
            splitAmount2: amount,
            startTime: lock.start + WEEK,
            endTime: lock.end + WEEK
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start + WEEK,
            end: lock.end + WEEK,
            cliff: lock.cliffLength + WEEK
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];

        // token 1 assertions
        assertEq(govNFT.locks(from).end, lock.end);
        assertEq(govNFT.locks(from).start, lock.start);
        assertEq(govNFT.locks(from).cliffLength, lock.cliffLength);
        assertEq(govNFT.ownerOf(from), address(recipient));

        // token 2 assertions
        IGovNFT.Lock memory splitLock = govNFT.locks(tokenId);

        assertEq(splitLock.end, lock.end + WEEK);
        assertEq(splitLock.start, lock.start + WEEK);
        assertEq(splitLock.cliffLength, lock.cliffLength + WEEK);
        assertEq(govNFT.ownerOf(tokenId), address(recipient2));

        skip(lock.end); // skips to end of tokenId1 vesting
        // vesting is finished for token1
        assertEq(govNFT.unclaimed(from), lock.totalLocked - amount);
        assertEq(govNFT.locked(from), 0);

        vm.prank(address(recipient));
        govNFT.claim(from, address(recipient), lock.totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), lock.totalLocked - amount);

        // vesting is not finished for token2
        assertLt(govNFT.unclaimed(tokenId), amount);
        assertGt(govNFT.locked(tokenId), 0);

        skip(splitLock.end); // skips to end of tokenId vesting
        // vesting is finished for token2
        assertEq(govNFT.unclaimed(tokenId), amount);
        assertEq(govNFT.locked(tokenId), 0);

        vm.prank(address(recipient2));
        govNFT.claim(tokenId, address(recipient2), lock.totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), amount);
    }

    function test_SplitToIncreaseStart(uint32 _delta) public {
        uint256 delta = uint256(_delta);
        IGovNFT.Lock memory lock = govNFT.locks(from);
        vm.assume(delta < lock.end - lock.start - lock.cliffLength); // avoid invalidcliff

        vm.prank(address(recipient));
        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: address(recipient2),
            splitAmount1: lock.totalLocked - amount,
            splitAmount2: amount,
            startTime: lock.start + delta,
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start + delta,
            end: lock.end,
            cliff: lock.cliffLength
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];

        // token 1 assertions
        assertEq(govNFT.locks(from).end, lock.end);
        assertEq(govNFT.locks(from).start, lock.start);
        assertEq(govNFT.locks(from).cliffLength, lock.cliffLength);
        assertEq(govNFT.ownerOf(from), address(recipient));

        // token 2 assertions
        IGovNFT.Lock memory splitLock = govNFT.locks(tokenId);

        assertEq(splitLock.end, lock.end);
        assertEq(splitLock.start, lock.start + delta);
        assertEq(splitLock.cliffLength, lock.cliffLength);
        assertEq(govNFT.ownerOf(tokenId), address(recipient2));
    }

    function test_SplitToIncreaseEnd(uint32 _delta) public {
        uint256 delta = uint256(_delta);
        IGovNFT.Lock memory lock = govNFT.locks(from);

        vm.prank(address(recipient));
        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: address(recipient2),
            splitAmount1: lock.totalLocked - amount,
            splitAmount2: amount,
            startTime: lock.start,
            endTime: lock.end + delta
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start,
            end: lock.end + delta,
            cliff: lock.cliffLength
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];

        // token 1 assertions
        assertEq(govNFT.locks(from).end, lock.end);
        assertEq(govNFT.locks(from).start, lock.start);
        assertEq(govNFT.locks(from).cliffLength, lock.cliffLength);
        assertEq(govNFT.ownerOf(from), address(recipient));

        // token 2 assertions
        IGovNFT.Lock memory splitLock = govNFT.locks(tokenId);

        assertEq(splitLock.start, lock.start);
        assertEq(splitLock.end, lock.end + delta);
        assertEq(splitLock.cliffLength, lock.cliffLength);
        assertEq(govNFT.ownerOf(tokenId), address(recipient2));
    }

    function test_SplitToIncreaseCliff(uint32 _cliff) public {
        uint256 delta = uint256(_cliff);
        IGovNFT.Lock memory lock = govNFT.locks(from);
        delta = bound(delta, 0, lock.end - lock.start - lock.cliffLength);

        vm.prank(address(recipient));
        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: address(recipient2),
            splitAmount1: lock.totalLocked - amount,
            splitAmount2: amount,
            startTime: lock.start,
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start,
            end: lock.end,
            cliff: lock.cliffLength + delta
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];

        // token 1 assertions
        assertEq(govNFT.locks(from).end, lock.end);
        assertEq(govNFT.locks(from).start, lock.start);
        assertEq(govNFT.locks(from).cliffLength, lock.cliffLength);
        assertEq(govNFT.ownerOf(from), address(recipient));

        // token 2 assertions
        IGovNFT.Lock memory splitLock = govNFT.locks(tokenId);

        assertEq(splitLock.start, lock.start);
        assertEq(splitLock.end, lock.end);
        assertEq(splitLock.cliffLength, lock.cliffLength + delta);
        assertEq(govNFT.ownerOf(tokenId), address(recipient2));
    }

    function test_SplitToIncreaseStartDecreaseCliff(uint32 _start, uint32 _cliff) public {
        uint256 startDelta = uint256(_start);
        IGovNFT.Lock memory lock = govNFT.locks(from);
        vm.assume(startDelta < lock.end - lock.start - lock.cliffLength); // avoid invalidcliff
        uint256 cliffDelta = uint256(_cliff);
        vm.assume(cliffDelta <= startDelta && cliffDelta <= lock.cliffLength);

        vm.prank(address(recipient));
        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split({
            from: from,
            tokenId: from + 1,
            recipient: address(recipient2),
            splitAmount1: lock.totalLocked - amount,
            splitAmount2: amount,
            startTime: lock.start + startDelta,
            endTime: lock.end
        });
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start + startDelta,
            end: lock.end,
            cliff: lock.cliffLength - cliffDelta
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];

        // token 1 assertions
        assertEq(govNFT.locks(from).end, lock.end);
        assertEq(govNFT.locks(from).start, lock.start);
        assertEq(govNFT.locks(from).cliffLength, lock.cliffLength);
        assertEq(govNFT.ownerOf(from), address(recipient));

        // token 2 assertions
        IGovNFT.Lock memory splitLock = govNFT.locks(tokenId);

        assertEq(splitLock.start, lock.start + startDelta);
        assertEq(splitLock.end, lock.end);
        assertEq(splitLock.cliffLength, lock.cliffLength - cliffDelta);
        assertEq(govNFT.ownerOf(tokenId), address(recipient2));
    }

    function test_RevertIf_SplitToInvalidStart() public {
        IGovNFT.Lock memory lock = govNFT.locks(from);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.InvalidStart.selector);
        // new vesting cannot start before original vesting starts
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start - 1,
            end: lock.end,
            cliff: lock.cliffLength
        });
        govNFT.split(from, paramsList);

        skip(WEEK + 1 days); //skip to after vesting start

        // start cannot be before block.timestamp, even if after original vesting starts
        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.InvalidStart.selector);
        paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start + 1,
            end: lock.end,
            cliff: lock.cliffLength
        });
        govNFT.split(from, paramsList);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.InvalidStart.selector);
        paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: block.timestamp - 1,
            end: lock.end,
            cliff: lock.cliffLength
        });
        govNFT.split(from, paramsList);
    }

    function test_RevertIf_SplitToInvalidEnd() public {
        IGovNFT.Lock memory lock = govNFT.locks(from);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.InvalidEnd.selector);
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start,
            end: lock.end - 1,
            cliff: lock.cliffLength
        });
        govNFT.split(from, paramsList);
    }

    function test_RevertIf_SplitToEndBeforeOrEqualStart() public {
        IGovNFT.Lock memory lock = govNFT.locks(from);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.EndBeforeOrEqualStart.selector);
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.end + 1,
            end: lock.end,
            cliff: 0
        });
        govNFT.split(from, paramsList);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.EndBeforeOrEqualStart.selector);
        paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.end,
            end: lock.end,
            cliff: 0
        });
        govNFT.split(from, paramsList);
    }

    function test_RevertIf_SplitToInvalidCliff() public {
        IGovNFT.Lock memory lock = govNFT.locks(from);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.InvalidCliff.selector);
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start,
            end: lock.end,
            cliff: lock.cliffLength - 1
        });
        govNFT.split(from, paramsList);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.InvalidCliff.selector);
        paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.end - lock.cliffLength / 2,
            end: lock.end,
            cliff: lock.cliffLength
        });
        govNFT.split(from, paramsList);
    }

    function test_RevertIf_SplitToZeroAddress() public {
        IGovNFT.Lock memory lock = govNFT.locks(from);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.ZeroAddress.selector);
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(0),
            amount: amount,
            start: lock.start,
            end: lock.end,
            cliff: lock.cliffLength
        });
        govNFT.split(from, paramsList);
    }
}
