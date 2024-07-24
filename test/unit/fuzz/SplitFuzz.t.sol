// SPDX-License-Identifier: GPL-3.0-or-later
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
        uint256 from = govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: lockAmount,
            _startTime: uint40(block.timestamp) + WEEK * 2,
            _endTime: uint40(block.timestamp) + WEEK * 3,
            _cliffLength: WEEK,
            _description: ""
        });
        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.totalLocked, govNFT.locked(from)); // no tokens have been vested before splitting
        assertEq(lock.splitCount, 0);

        skip(timeskip);

        vm.expectEmit(true, true, true, true);
        emit IGovNFT.Split({
            from: from,
            to: from + 1,
            recipient: address(recipient2),
            splitAmount1: lock.totalLocked - amount,
            splitAmount2: amount,
            startTime: lock.start,
            endTime: lock.end,
            description: ""
        });
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start,
            end: lock.end,
            cliff: WEEK,
            description: ""
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
        uint256 from = govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: lockAmount,
            _startTime: uint40(block.timestamp) + WEEK * 2,
            _endTime: uint40(block.timestamp) + WEEK * 3,
            _cliffLength: WEEK,
            _description: ""
        });

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.totalLocked, govNFT.locked(from)); // no tokens have been vested before splitting
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.splitCount, 0);

        skip(timeskip);

        vm.expectEmit(true, true, true, true);
        emit IGovNFT.Split({
            from: from,
            to: from + 1,
            recipient: address(recipient2),
            splitAmount1: lock.totalLocked - amount,
            splitAmount2: amount,
            startTime: lock.start,
            endTime: lock.end,
            description: ""
        });
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start,
            end: lock.end,
            cliff: WEEK,
            description: ""
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];
        _checkLockedUnclaimedSplit(from, lock.totalLocked - amount, 0, tokenId, amount, 0);

        // split NFT assertions
        vm.warp(govNFT.locks(tokenId).end);

        _checkLockedUnclaimedSplit(from, 0, lock.totalLocked - amount, tokenId, 0, amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        vm.prank(address(recipient));
        govNFT.claim({_tokenId: from, _beneficiary: address(recipient), _amount: lock.totalLocked});
        assertEq(IERC20(testToken).balanceOf(address(recipient)), lock.totalLocked - amount);

        vm.prank(address(recipient2));
        govNFT.claim({_tokenId: tokenId, _beneficiary: address(recipient2), _amount: lock.totalLocked});
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), amount);
    }

    function testFuzz_SplitBeforeCliffEnd(uint128 lockAmount, uint256 amount, uint32 timeskip) public {
        vm.assume(lockAmount > 2);
        timeskip = uint32(bound(timeskip, 0, WEEK * 3 - 1));
        amount = bound(amount, 1, uint256(lockAmount));
        deal(testToken, address(admin), uint256(lockAmount));

        admin.approve(testToken, address(govNFT), uint256(lockAmount));
        vm.prank(address(admin));
        uint256 from = govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: uint256(lockAmount),
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 4,
            _cliffLength: WEEK * 3,
            _description: ""
        });

        skip(timeskip); // skip somewhere before cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.totalLocked, govNFT.locked(from)); // still on cliff, no tokens vested
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.splitCount, 0);

        vm.expectEmit(true, true, true, true);
        emit IGovNFT.Split({
            from: from,
            to: from + 1,
            recipient: address(recipient2),
            splitAmount1: lock.totalLocked - amount,
            splitAmount2: amount,
            startTime: uint40(block.timestamp),
            endTime: lock.end,
            description: ""
        });
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        uint40 remainingCliff = (lock.start + lock.cliffLength) - uint40(block.timestamp);
        assertEq(remainingCliff, lock.cliffLength - timeskip);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: remainingCliff,
            description: ""
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];

        // original NFT assertions
        _checkLockUpdates(from, lock.totalLocked - amount, lock.totalLocked, lock.cliffLength, lock.start, lock.end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), 0, 1);

        // split NFT assertions
        _checkLockUpdates(tokenId, amount, amount, remainingCliff, uint40(block.timestamp), lock.end);
    }

    function testFuzz_SplitClaimsBeforeCliffEnd(uint128 lockAmount, uint256 amount, uint32 timeskip) public {
        vm.assume(lockAmount > 2);
        timeskip = uint32(bound(timeskip, 0, WEEK * 3 - 1));
        amount = bound(amount, 1, uint256(lockAmount));
        deal(testToken, address(admin), uint256(lockAmount));

        admin.approve(testToken, address(govNFT), uint256(lockAmount));
        vm.prank(address(admin));
        uint256 from = govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: uint256(lockAmount),
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 4,
            _cliffLength: WEEK * 3,
            _description: ""
        });

        skip(timeskip); // skip somewhere before cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.totalLocked, govNFT.locked(from)); // still on cliff, no tokens vested
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.splitCount, 0);

        vm.expectEmit(true, true, true, true);
        emit IGovNFT.Split({
            from: from,
            to: from + 1,
            recipient: address(recipient2),
            splitAmount1: lock.totalLocked - amount,
            splitAmount2: amount,
            startTime: uint40(block.timestamp),
            endTime: lock.end,
            description: ""
        });
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: WEEK * 3 - timeskip,
            description: ""
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];
        _checkLockedUnclaimedSplit(from, lock.totalLocked - amount, 0, tokenId, amount, 0);

        vm.warp(govNFT.locks(tokenId).end);

        _checkLockedUnclaimedSplit(from, 0, lock.totalLocked - amount, tokenId, 0, amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        vm.prank(address(recipient));
        govNFT.claim({_tokenId: from, _beneficiary: address(recipient), _amount: lock.totalLocked});
        assertEq(IERC20(testToken).balanceOf(address(recipient)), lock.totalLocked - amount);

        vm.prank(address(recipient2));
        govNFT.claim({_tokenId: tokenId, _beneficiary: address(recipient2), _amount: lock.totalLocked});
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), amount);
    }

    function testFuzz_SplitAfterCliffEnd(uint128 lockAmount, uint256 amount, uint32 timeskip) public {
        vm.assume(lockAmount > 3); // to avoid bound reverts
        timeskip = uint32(bound(timeskip, WEEK, WEEK * 6));
        deal(testToken, address(admin), uint256(lockAmount));

        admin.approve(testToken, address(govNFT), uint256(lockAmount));
        vm.prank(address(admin));
        uint256 from = govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: uint256(lockAmount),
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 6,
            _cliffLength: WEEK,
            _description: ""
        });

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

        vm.expectEmit(true, true, true, true);
        emit IGovNFT.Split({
            from: from,
            to: from + 1,
            recipient: address(recipient2),
            splitAmount1: lockedBeforeSplit - amount,
            splitAmount2: amount,
            startTime: uint40(block.timestamp),
            endTime: lock.end,
            description: ""
        });
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: 0,
            description: ""
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];

        // unclaimed and locked remain untouched
        assertEq(lockedBeforeSplit + originalUnclaimedBeforeSplit, uint256(lockAmount));
        assertEq(govNFT.locked(from), lockedBeforeSplit - amount);
        assertEq(govNFT.unclaimed(from), originalUnclaimedBeforeSplit);

        // original NFT assertions
        // no cliff since vesting has already started
        _checkLockUpdates(from, lockedBeforeSplit - amount, lock.totalLocked, 0, uint40(block.timestamp), lock.end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), originalUnclaimedBeforeSplit, 1);
        assertEq(govNFT.locked(from), govNFT.locks(from).totalLocked);

        // split NFT assertions
        assertEq(govNFT.locked(tokenId), govNFT.locks(tokenId).totalLocked);

        // no cliff since vesting has already started
        _checkLockUpdates(tokenId, amount, amount, 0, uint40(block.timestamp), lock.end);
    }

    function testFuzz_SplitClaimsAfterCliffEnd(uint128 lockAmount, uint256 amount, uint32 timeskip) public {
        vm.assume(lockAmount > 3); // to avoid bound reverts
        timeskip = uint32(bound(timeskip, WEEK, WEEK * 6));
        deal(testToken, address(admin), uint256(lockAmount));

        admin.approve(testToken, address(govNFT), uint256(lockAmount));
        vm.prank(address(admin));
        uint256 from = govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: uint256(lockAmount),
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 6,
            _cliffLength: WEEK,
            _description: ""
        });

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

        vm.expectEmit(true, true, true, true);
        emit IGovNFT.Split({
            from: from,
            to: from + 1,
            recipient: address(recipient2),
            splitAmount1: lockedBeforeSplit - amount,
            splitAmount2: amount,
            startTime: uint40(block.timestamp),
            endTime: lock.end,
            description: ""
        });
        vm.prank(address(recipient));

        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: 0,
            description: ""
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
        govNFT.claim({_tokenId: tokenId, _beneficiary: address(recipient2), _amount: lockAmount});
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), amount);

        vm.prank(address(recipient));
        govNFT.claim({_tokenId: from, _beneficiary: address(recipient), _amount: lockAmount});
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
        uint256 from = govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: uint256(lockAmount),
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 6,
            _cliffLength: WEEK,
            _description: ""
        });

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

        vm.expectEmit(true, true, true, true);
        emit IGovNFT.Split({
            from: from,
            to: from + 1,
            recipient: address(recipient2),
            splitAmount1: lockedBeforeSplit - amount,
            splitAmount2: amount,
            startTime: uint40(block.timestamp),
            endTime: lock.end,
            description: ""
        });
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: 0,
            description: ""
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];
        _checkLockedUnclaimedSplit(from, lockedBeforeSplit - amount, originalUnclaimedBeforeSplit, tokenId, amount, 0);

        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        // nothing to claim on split token in split timestamp
        vm.prank(address(recipient2));
        govNFT.claim({_tokenId: tokenId, _beneficiary: address(recipient2), _amount: lockAmount});
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(govNFT.locks(tokenId).totalClaimed, 0);

        vm.prank(address(recipient));
        govNFT.claim({_tokenId: from, _beneficiary: address(recipient), _amount: lockAmount});
        assertEq(IERC20(testToken).balanceOf(address(recipient)), originalUnclaimedBeforeSplit);
        assertEq(govNFT.locks(from).totalClaimed, 0); // unclaimed before split not included
    }
}
