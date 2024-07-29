// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract SplitFuzzTest is BaseTest {
    uint256 public from;
    uint256 public amount;

    function _setUp() public override {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        from = govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_100K,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 3,
            _cliffLength: WEEK,
            _description: ""
        });
        amount = TOKEN_10K * 4;
    }

    function testFuzz_SplitBeforeStart(uint128 lockAmount, uint256 splitAmount, uint32 timeskip) public {
        vm.assume(lockAmount > 2);
        timeskip = uint32(bound(timeskip, 0, WEEK * 2));
        amount = bound(splitAmount, 1, uint256(lockAmount));
        deal(testToken, address(admin), uint256(lockAmount));

        admin.approve(testToken, address(govNFT), uint256(lockAmount));
        vm.prank(address(admin));
        from = govNFT.createLock({
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

        vm.expectEmit(address(govNFT));
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

    function testFuzz_SplitClaimsBeforeStart(uint128 lockAmount, uint256 splitAmount, uint32 timeskip) public {
        vm.assume(lockAmount > 2);
        timeskip = uint32(bound(timeskip, 0, WEEK * 2));
        amount = bound(splitAmount, 1, uint256(lockAmount));
        deal(testToken, address(admin), uint256(lockAmount));

        admin.approve(testToken, address(govNFT), uint256(lockAmount));
        vm.prank(address(admin));
        from = govNFT.createLock({
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

        vm.expectEmit(address(govNFT));
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

    function testFuzz_SplitBeforeCliffEnd(uint128 lockAmount, uint256 splitAmount, uint32 timeskip) public {
        vm.assume(lockAmount > 2);
        timeskip = uint32(bound(timeskip, 0, WEEK * 3 - 1));
        amount = bound(splitAmount, 1, uint256(lockAmount));
        deal(testToken, address(admin), uint256(lockAmount));

        admin.approve(testToken, address(govNFT), uint256(lockAmount));
        vm.prank(address(admin));
        from = govNFT.createLock({
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

        vm.expectEmit(address(govNFT));
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

    function testFuzz_SplitClaimsBeforeCliffEnd(uint128 lockAmount, uint256 splitAmount, uint32 timeskip) public {
        vm.assume(lockAmount > 2);
        timeskip = uint32(bound(timeskip, 0, WEEK * 3 - 1));
        amount = bound(splitAmount, 1, uint256(lockAmount));
        deal(testToken, address(admin), uint256(lockAmount));

        admin.approve(testToken, address(govNFT), uint256(lockAmount));
        vm.prank(address(admin));
        from = govNFT.createLock({
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

        vm.expectEmit(address(govNFT));
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

    function testFuzz_SplitAfterCliffEnd(uint128 lockAmount, uint256 splitAmount, uint32 timeskip) public {
        vm.assume(lockAmount > 3); // to avoid bound reverts
        timeskip = uint32(bound(timeskip, WEEK, WEEK * 6));
        deal(testToken, address(admin), uint256(lockAmount));

        admin.approve(testToken, address(govNFT), uint256(lockAmount));
        vm.prank(address(admin));
        from = govNFT.createLock({
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
        amount = bound(splitAmount, 1, lockedBeforeSplit - 1); // amount to split has to be lower than locked value

        vm.expectEmit(address(govNFT));
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

    function testFuzz_SplitClaimsAfterCliffEnd(uint128 lockAmount, uint256 splitAmount, uint32 timeskip) public {
        vm.assume(lockAmount > 3); // to avoid bound reverts
        timeskip = uint32(bound(timeskip, WEEK, WEEK * 6));
        deal(testToken, address(admin), uint256(lockAmount));

        admin.approve(testToken, address(govNFT), uint256(lockAmount));
        vm.prank(address(admin));
        from = govNFT.createLock({
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
        amount = bound(splitAmount, 1, lockedBeforeSplit);

        vm.expectEmit(address(govNFT));
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
        uint256 splitAmount,
        uint32 timeskip
    ) public {
        vm.assume(lockAmount > 3); // to avoid bound reverts
        timeskip = uint32(bound(timeskip, WEEK, WEEK * 6));
        deal(testToken, address(admin), uint256(lockAmount));

        admin.approve(testToken, address(govNFT), uint256(lockAmount));
        vm.prank(address(admin));
        from = govNFT.createLock({
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
        amount = bound(splitAmount, 1, lockedBeforeSplit);

        vm.expectEmit(address(govNFT));
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

    function testFuzz_SplitToIncreaseStart(uint40 delta) public {
        IGovNFT.Lock memory lock = govNFT.locks(from);
        delta = uint40(bound(delta, 0, lock.end - lock.start - lock.cliffLength)); // avoid invalidcliff

        vm.prank(address(recipient));
        vm.expectEmit(address(govNFT));
        emit IGovNFT.Split({
            from: from,
            to: from + 1,
            recipient: address(recipient2),
            splitAmount1: lock.totalLocked - amount,
            splitAmount2: amount,
            startTime: lock.start + delta,
            endTime: lock.end,
            description: ""
        });
        vm.expectEmit(address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start + delta,
            end: lock.end,
            cliff: lock.cliffLength,
            description: ""
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

    function testFuzz_SplitToIncreaseEnd(uint40 delta) public {
        IGovNFT.Lock memory lock = govNFT.locks(from);
        delta = uint40(bound(delta, 0, type(uint40).max - lock.end)); // avoid overflow

        vm.prank(address(recipient));
        vm.expectEmit(address(govNFT));
        emit IGovNFT.Split({
            from: from,
            to: from + 1,
            recipient: address(recipient2),
            splitAmount1: lock.totalLocked - amount,
            splitAmount2: amount,
            startTime: lock.start,
            endTime: lock.end + delta,
            description: ""
        });
        vm.expectEmit(address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start,
            end: lock.end + delta,
            cliff: lock.cliffLength,
            description: ""
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

    function testFuzz_SplitToIncreaseCliff(uint40 cliffDelta) public {
        IGovNFT.Lock memory lock = govNFT.locks(from);
        cliffDelta = uint40(bound(cliffDelta, 0, lock.end - lock.start - lock.cliffLength));

        vm.prank(address(recipient));
        vm.expectEmit(address(govNFT));
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
        vm.expectEmit(address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start,
            end: lock.end,
            cliff: lock.cliffLength + cliffDelta,
            description: ""
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
        assertEq(splitLock.cliffLength, lock.cliffLength + cliffDelta);
        assertEq(govNFT.ownerOf(tokenId), address(recipient2));
    }

    function testFuzz_SplitToIncreaseStartDecreaseCliff(uint40 startDelta, uint40 cliffDelta) public {
        IGovNFT.Lock memory lock = govNFT.locks(from);
        startDelta = uint40(bound(startDelta, 0, lock.end - lock.start - lock.cliffLength)); // avoid invalidcliff
        cliffDelta = uint40(bound(cliffDelta, 0, Math.min(startDelta, lock.cliffLength)));

        vm.prank(address(recipient));
        vm.expectEmit(address(govNFT));
        emit IGovNFT.Split({
            from: from,
            to: from + 1,
            recipient: address(recipient2),
            splitAmount1: lock.totalLocked - amount,
            splitAmount2: amount,
            startTime: lock.start + startDelta,
            endTime: lock.end,
            description: ""
        });
        vm.expectEmit(address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start + startDelta,
            end: lock.end,
            cliff: lock.cliffLength - cliffDelta,
            description: ""
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

    function testFuzz_SplitTokensByIndex(uint8 splits) public {
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
                start: uint40(block.timestamp),
                end: uint40(block.timestamp) + WEEK * 3,
                cliff: WEEK,
                description: ""
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
}
