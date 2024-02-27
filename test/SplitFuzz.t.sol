// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract SplitFuzzTest is BaseTest {
    function testFuzz_SplitBeforeStart(uint128 lockAmount, uint256 amount, uint32 timeskip) public {
        vm.assume(lockAmount > 2);
        timeskip = uint32(bound(timeskip, 0, WEEK * 2));
        amount = bound(amount, 1, uint256(lockAmount));
        deal(testToken, address(admin), uint256(lockAmount));

        admin.approve(testToken, address(govNFT), uint256(lockAmount));
        vm.prank(address(admin));
        uint256 from = govNFT.createLock(
            testToken,
            address(recipient),
            lockAmount,
            block.timestamp + WEEK * 2,
            block.timestamp + WEEK * 3,
            WEEK
        );
        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.totalLocked, govNFT.locked(from)); // no tokens have been vested before splitting
        assertEq(lock.splitCount, 0);

        skip(timeskip);

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

        // original NFT assertions
        // start timestamps and cliffs remain the same as parent token, since vesting has not started
        _checkLockUpdates(from, lock.totalLocked - amount, lock.totalLocked, lock.cliffLength, lock.start, lock.end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), 0, 1);

        // split NFT assertions
        // start timestamps and cliffs remain the same as parent token
        _checkLockUpdates(tokenId, amount, amount, lock.cliffLength, lock.start, lock.end);
    }

    function testFuzz_SplitClaimsBeforeStart(uint128 lockAmount, uint256 amount, uint32 timeskip) public {
        vm.assume(lockAmount > 2);
        timeskip = uint32(bound(timeskip, 0, WEEK * 2));
        amount = bound(amount, 1, uint256(lockAmount));
        deal(testToken, address(admin), uint256(lockAmount));

        admin.approve(testToken, address(govNFT), uint256(lockAmount));
        vm.prank(address(admin));
        uint256 from = govNFT.createLock(
            testToken,
            address(recipient),
            lockAmount,
            block.timestamp + WEEK * 2,
            block.timestamp + WEEK * 3,
            WEEK
        );

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.totalLocked, govNFT.locked(from)); // no tokens have been vested before splitting
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.splitCount, 0);

        skip(timeskip);

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

        // split NFT assertions
        vm.warp(govNFT.locks(tokenId).end);

        _checkLockedUnclaimedSplit(from, 0, lock.totalLocked - amount, tokenId, 0, amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        vm.prank(address(recipient));
        govNFT.claim(from, address(recipient), lock.totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), lock.totalLocked - amount);

        vm.prank(address(recipient2));
        govNFT.claim(tokenId, address(recipient2), lock.totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), amount);
    }

    function testFuzz_SplitBeforeCliffEnd(uint128 lockAmount, uint256 amount, uint32 timeskip) public {
        vm.assume(lockAmount > 2);
        timeskip = uint32(bound(timeskip, 0, WEEK * 3 - 1));
        amount = bound(amount, 1, uint256(lockAmount));
        deal(testToken, address(admin), uint256(lockAmount));

        admin.approve(testToken, address(govNFT), uint256(lockAmount));
        vm.prank(address(admin));
        uint256 from = govNFT.createLock(
            testToken,
            address(recipient),
            uint256(lockAmount),
            block.timestamp,
            block.timestamp + WEEK * 4,
            WEEK * 3
        );

        skip(timeskip); // skip somewhere before cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.totalLocked, govNFT.locked(from)); // still on cliff, no tokens vested
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.splitCount, 0);

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
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: block.timestamp,
            end: lock.end,
            cliff: lock.cliffLength - timeskip
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];

        // original NFT assertions
        uint256 remainingCliff = (lock.start + lock.cliffLength) - block.timestamp;
        _checkLockUpdates(from, lock.totalLocked - amount, lock.totalLocked, remainingCliff, block.timestamp, lock.end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), 0, 1);
        assertEq(remainingCliff, lock.cliffLength - timeskip);

        // split NFT assertions
        _checkLockUpdates(tokenId, amount, amount, remainingCliff, block.timestamp, lock.end);
    }

    function testFuzz_SplitClaimsBeforeCliffEnd(uint128 lockAmount, uint256 amount, uint32 timeskip) public {
        vm.assume(lockAmount > 2);
        timeskip = uint32(bound(timeskip, 0, WEEK * 3 - 1));
        amount = bound(amount, 1, uint256(lockAmount));
        deal(testToken, address(admin), uint256(lockAmount));

        admin.approve(testToken, address(govNFT), uint256(lockAmount));
        vm.prank(address(admin));
        uint256 from = govNFT.createLock(
            testToken,
            address(recipient),
            uint256(lockAmount),
            block.timestamp,
            block.timestamp + WEEK * 4,
            WEEK * 3
        );

        skip(timeskip); // skip somewhere before cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.totalLocked, govNFT.locked(from)); // still on cliff, no tokens vested
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.splitCount, 0);

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
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: block.timestamp,
            end: lock.end,
            cliff: WEEK * 3 - timeskip
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];
        _checkLockedUnclaimedSplit(from, lock.totalLocked - amount, 0, tokenId, amount, 0);

        vm.warp(govNFT.locks(tokenId).end);

        _checkLockedUnclaimedSplit(from, 0, lock.totalLocked - amount, tokenId, 0, amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        vm.prank(address(recipient));
        govNFT.claim(from, address(recipient), lock.totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), lock.totalLocked - amount);

        vm.prank(address(recipient2));
        govNFT.claim(tokenId, address(recipient2), lock.totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), amount);
    }

    function testFuzz_SplitAfterCliffEnd(uint128 lockAmount, uint256 amount, uint32 timeskip) public {
        vm.assume(lockAmount > 3); // to avoid bound reverts
        timeskip = uint32(bound(timeskip, WEEK, WEEK * 6));
        deal(testToken, address(admin), uint256(lockAmount));

        admin.approve(testToken, address(govNFT), uint256(lockAmount));
        vm.prank(address(admin));
        uint256 from = govNFT.createLock(
            testToken,
            address(recipient),
            uint256(lockAmount),
            block.timestamp,
            block.timestamp + WEEK * 6,
            WEEK
        );

        skip(timeskip); // skip somewhere after cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.splitCount, 0);
        uint256 lockedBeforeSplit = govNFT.locked(from);
        // can only split if locked is greater than 1
        while (lockedBeforeSplit <= 1) {
            rewind(1 days);
            lockedBeforeSplit = govNFT.locked(from);
        }
        uint256 originalUnclaimedBeforeSplit = govNFT.unclaimed(from);
        amount = bound(amount, 1, lockedBeforeSplit - 1); // amount to split has to be lower than locked value

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

        // unclaimed and locked remain untouched
        assertEq(lockedBeforeSplit + originalUnclaimedBeforeSplit, uint256(lockAmount));
        assertEq(govNFT.locked(from), lockedBeforeSplit - amount);
        assertEq(govNFT.unclaimed(from), originalUnclaimedBeforeSplit);

        // original NFT assertions
        // no cliff since vesting has already started
        _checkLockUpdates(from, lockedBeforeSplit - amount, lock.totalLocked, 0, block.timestamp, lock.end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), originalUnclaimedBeforeSplit, 1);
        assertEq(govNFT.locked(from), govNFT.locks(from).totalLocked);

        // split NFT assertions
        assertEq(govNFT.locked(tokenId), govNFT.locks(tokenId).totalLocked);

        // no cliff since vesting has already started
        _checkLockUpdates(tokenId, amount, amount, 0, block.timestamp, lock.end);
    }

    function testFuzz_SplitClaimsAfterCliffEnd(uint128 lockAmount, uint256 amount, uint32 timeskip) public {
        vm.assume(lockAmount > 3); // to avoid bound reverts
        timeskip = uint32(bound(timeskip, WEEK, WEEK * 6));
        deal(testToken, address(admin), uint256(lockAmount));

        admin.approve(testToken, address(govNFT), uint256(lockAmount));
        vm.prank(address(admin));
        uint256 from = govNFT.createLock(
            testToken,
            address(recipient),
            uint256(lockAmount),
            block.timestamp,
            block.timestamp + WEEK * 6,
            WEEK
        );

        skip(timeskip); // skip somewhere after cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.splitCount, 0);
        uint256 lockedBeforeSplit = govNFT.locked(from);
        // can only split if locked is equal or greater than 1
        while (lockedBeforeSplit < 1) {
            rewind(1 days);
            lockedBeforeSplit = govNFT.locked(from);
        }
        uint256 originalUnclaimedBeforeSplit = govNFT.unclaimed(from);
        amount = bound(amount, 1, lockedBeforeSplit);

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
        _checkLockedUnclaimedSplit(from, lockedBeforeSplit - amount, originalUnclaimedBeforeSplit, tokenId, amount, 0);

        vm.warp(govNFT.locks(tokenId).end);

        _checkLockedUnclaimedSplit(
            from,
            0,
            originalUnclaimedBeforeSplit + lockedBeforeSplit - amount,
            tokenId,
            0,
            amount
        );
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        vm.prank(address(recipient2));
        govNFT.claim(tokenId, address(recipient2), lockAmount);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), amount);

        vm.prank(address(recipient));
        govNFT.claim(from, address(recipient), lockAmount);
        assertEq(
            IERC20(testToken).balanceOf(address(recipient)),
            lockedBeforeSplit + originalUnclaimedBeforeSplit - amount
        );
    }

    function testFuzz_SplitClaimsAtSplitTimestampAfterCliffEnd(
        uint128 lockAmount,
        uint256 amount,
        uint32 timeskip
    ) public {
        vm.assume(lockAmount > 3); // to avoid bound reverts
        timeskip = uint32(bound(timeskip, WEEK, WEEK * 6));
        deal(testToken, address(admin), uint256(lockAmount));

        admin.approve(testToken, address(govNFT), uint256(lockAmount));
        vm.prank(address(admin));
        uint256 from = govNFT.createLock(
            testToken,
            address(recipient),
            uint256(lockAmount),
            block.timestamp,
            block.timestamp + WEEK * 6,
            WEEK
        );

        skip(timeskip); // skip somewhere after cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.splitCount, 0);
        uint256 lockedBeforeSplit = govNFT.locked(from);
        // can only split if locked is equal or greater than 1
        while (lockedBeforeSplit < 1) {
            rewind(1 days);
            lockedBeforeSplit = govNFT.locked(from);
        }
        uint256 originalUnclaimedBeforeSplit = govNFT.unclaimed(from);
        amount = bound(amount, 1, lockedBeforeSplit);

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
        _checkLockedUnclaimedSplit(from, lockedBeforeSplit - amount, originalUnclaimedBeforeSplit, tokenId, amount, 0);

        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        // nothing to claim on split token in split timestamp
        vm.prank(address(recipient2));
        govNFT.claim(tokenId, address(recipient2), lockAmount);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(govNFT.locks(tokenId).totalClaimed, 0);

        vm.prank(address(recipient));
        govNFT.claim(from, address(recipient), lockAmount);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), originalUnclaimedBeforeSplit);
        assertEq(govNFT.locks(from).totalClaimed, 0); // unclaimed before split not included
    }
}
