// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract SplitTest is BaseTest {
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

    function test_SplitBeforeStart() public {
        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.totalLocked, govNFT.locked(from)); // no tokens have been vested before splitting
        assertEq(lock.splitCount, 0);
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked);

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
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start,
            end: lock.end,
            cliff: lock.cliffLength,
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

    function test_SplitClaimsBeforeStart() public {
        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.totalClaimed, 0);

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

        vm.warp(govNFT.locks(tokenId).end); // Warp to end of Split Lock vesting

        _checkLockedUnclaimedSplit(from, 0, lock.totalLocked - amount, tokenId, 0, amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        // assert claims
        assertEq(govNFT.locks(from).totalClaimed, 0);
        vm.prank(address(recipient));
        govNFT.claim({_tokenId: from, _beneficiary: address(recipient), _amount: lock.totalLocked});
        assertEq(IERC20(testToken).balanceOf(address(recipient)), lock.totalLocked - amount);
        assertEq(govNFT.locks(from).totalClaimed, lock.totalLocked - amount);

        assertEq(govNFT.locks(tokenId).totalClaimed, 0);
        vm.prank(address(recipient2));
        govNFT.claim({_tokenId: tokenId, _beneficiary: address(recipient2), _amount: lock.totalLocked});
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
        uint40 remainingCliff = (lock.start + lock.cliffLength) - uint40(block.timestamp);
        assertEq(remainingCliff, WEEK - 5 days);

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
        vm.expectEmit(address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
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
        // since still on cliff and vesting has started, the lock timestamps remain the same
        _checkLockUpdates(from, lock.totalLocked - amount, lock.totalLocked, lock.cliffLength, lock.start, lock.end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), 0, 1);

        // split NFT assertions
        _checkLockUpdates(tokenId, amount, amount, remainingCliff, uint40(block.timestamp), lock.end);
    }

    function test_SplitClaimsBeforeCliffEnd() public {
        skip(5 days); // skip somewhere before cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.totalClaimed, 0);

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
        vm.expectEmit(address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: WEEK - 5 days,
            description: ""
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
        govNFT.claim({_tokenId: from, _beneficiary: address(recipient), _amount: lock.totalLocked});
        assertEq(IERC20(testToken).balanceOf(address(recipient)), lock.totalLocked - amount);
        assertEq(govNFT.locks(from).totalClaimed, lock.totalLocked - amount);

        assertEq(govNFT.locks(tokenId).totalClaimed, 0);
        vm.prank(address(recipient2));
        govNFT.claim({_tokenId: tokenId, _beneficiary: address(recipient2), _amount: lock.totalLocked});
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), amount);
        assertEq(govNFT.locks(tokenId).totalClaimed, amount);
    }

    function test_SplitBeforeCliffEndMaintainsCliffVesting() public {
        skip(5 days); // skip somewhere before cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.totalLocked, govNFT.locked(from)); // still on cliff, no tokens vested
        uint40 remainingCliff = (lock.start + lock.cliffLength) - uint40(block.timestamp);
        assertEq(remainingCliff, WEEK - 5 days);

        uint256 lockedAfterSplit = lock.totalLocked - amount;
        uint256 expectedVestAfterCliff = (lockedAfterSplit * lock.cliffLength) / (lock.end - lock.start);

        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: remainingCliff,
            description: ""
        });
        govNFT.split(from, paramsList);

        lock = govNFT.locks(from);

        skip(remainingCliff); // skip to end of cliff

        // Claimable after cliff should remain the same after splitting
        assertEq(govNFT.unclaimed(from), expectedVestAfterCliff);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        vm.prank(address(recipient));
        govNFT.claim(from, address(recipient2), type(uint256).max);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), expectedVestAfterCliff);
    }

    function test_SplitAfterCliffEnd() public {
        skip(WEEK + 2 days); // skip somewhere after cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.splitCount, 0);
        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked);

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
        vm.expectEmit(address(govNFT));
        emit IERC4906.MetadataUpdate(from);
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

        assertEq(lock.totalLocked, govNFT.locked(from) + govNFT.locked(tokenId) + originalUnclaimed);

        // original NFT assertions
        uint256 totalLockedSplit = govNFT.locks(from).totalLocked;

        // no cliff since vesting has already started
        _checkLockUpdates(from, lockedBeforeSplit - amount, lock.totalLocked, 0, uint40(block.timestamp), lock.end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), originalUnclaimed, 1);
        assertEq(govNFT.locked(from), totalLockedSplit);

        // split NFT assertions
        totalLockedSplit = govNFT.locks(tokenId).totalLocked;

        // no cliff since vesting has already started
        _checkLockUpdates(tokenId, amount, amount, 0, uint40(block.timestamp), lock.end);

        assertEq(govNFT.locked(tokenId), totalLockedSplit);
    }

    function test_SplitAfterCliffEndAndClaim() public {
        skip(WEEK + 2 days); // skip somewhere after cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.splitCount, 0);

        vm.prank(address(recipient));
        govNFT.claim({_tokenId: from, _beneficiary: address(recipient), _amount: lock.totalLocked});
        lock = govNFT.locks(from);

        skip(2 days); // skip somewhere before vesting ends to vest more rewards
        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked - lock.totalClaimed);

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
        vm.expectEmit(address(govNFT));
        emit IERC4906.MetadataUpdate(from);
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

        assertEq(
            lock.totalLocked,
            govNFT.locked(from) + govNFT.locked(tokenId) + originalUnclaimed + lock.totalClaimed
        );

        // original NFT assertions
        uint256 totalLockedSplit = govNFT.locks(from).totalLocked;

        // no cliff since vesting has already started
        _checkLockUpdates(from, lockedBeforeSplit - amount, lock.totalLocked, 0, uint40(block.timestamp), lock.end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), originalUnclaimed, 1);
        assertEq(govNFT.locked(from), totalLockedSplit);

        // split NFT assertions
        totalLockedSplit = govNFT.locks(tokenId).totalLocked;

        // no cliff since vesting has already started
        _checkLockUpdates(tokenId, amount, amount, 0, uint40(block.timestamp), lock.end);
        assertEq(govNFT.locked(tokenId), totalLockedSplit);
    }

    function test_SplitClaimsWithUnclaimedRewardsAfterCliffEnd() public {
        skip(WEEK + 2 days); // skip somewhere after cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.totalClaimed, 0);
        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);

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
        vm.expectEmit(address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: WEEK,
            description: ""
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
        govNFT.claim({_tokenId: from, _beneficiary: address(recipient), _amount: lock.totalLocked});
        assertEq(IERC20(testToken).balanceOf(address(recipient)), originalUnclaimed + lockedBeforeSplit - amount);
        assertEq(govNFT.locks(from).totalClaimed, lockedBeforeSplit - amount); //unclaimed before split not included

        vm.prank(address(recipient2));
        govNFT.claim({_tokenId: tokenId, _beneficiary: address(recipient2), _amount: lock.totalLocked});
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
        vm.expectEmit(address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: WEEK,
            description: ""
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
        govNFT.claim({_tokenId: from, _beneficiary: address(recipient), _amount: lock.totalLocked});
        assertEq(IERC20(testToken).balanceOf(address(recipient)), originalUnclaimed);
        assertEq(govNFT.locks(from).totalClaimed, 0); // unclaimed before split not included

        // nothing to claim on split token in split timestamp
        vm.prank(address(recipient2));
        govNFT.claim({_tokenId: tokenId, _beneficiary: address(recipient2), _amount: lock.totalLocked});
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
        govNFT.claim({_tokenId: from, _beneficiary: address(recipient), _amount: lock.totalLocked});
        assertEq(IERC20(testToken).balanceOf(address(recipient)), originalUnclaimed);
        assertEq(govNFT.locks(from).totalClaimed, originalUnclaimed);
        assertEq(govNFT.unclaimed(from), 0);

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
        vm.expectEmit(address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: WEEK,
            description: ""
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
        govNFT.claim({_tokenId: from, _beneficiary: address(recipient), _amount: lock.totalLocked});
        assertEq(IERC20(testToken).balanceOf(address(recipient)), originalUnclaimed + lockedBeforeSplit - amount);
        assertEq(govNFT.locks(from).totalClaimed, lockedBeforeSplit - amount); //unclaimed before split not included

        vm.prank(address(recipient2));
        govNFT.claim({_tokenId: tokenId, _beneficiary: address(recipient2), _amount: lock.totalLocked});
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), amount);
        assertEq(govNFT.locks(tokenId).totalClaimed, amount);
    }

    function test_SplitWithUnclaimedRewardsAndSweep() public {
        skip((WEEK * 3) / 2); // skip halfway through vestment

        vm.startPrank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: uint40(block.timestamp),
            end: govNFT.locks(from).end,
            cliff: 0,
            description: ""
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];

        uint256 unclaimedRewards = govNFT.unclaimed(from);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);

        // sweep does not allow to claim any vested tokens
        vm.expectRevert(IGovNFT.ZeroAmount.selector);
        govNFT.sweep({_tokenId: from, _token: testToken, _recipient: address(recipient)});

        govNFT.claim({_tokenId: from, _beneficiary: address(recipient), _amount: type(uint256).max});
        assertEq(IERC20(testToken).balanceOf(address(recipient)), unclaimedRewards);

        assertEq(govNFT.unclaimed(tokenId), 0);
        // sweep does not allow to claim any vested tokens
        vm.startPrank(address(recipient2));
        vm.expectRevert(IGovNFT.ZeroAmount.selector);
        govNFT.sweep({_tokenId: tokenId, _token: testToken, _recipient: address(recipient2)});

        govNFT.claim({_tokenId: tokenId, _beneficiary: address(recipient2), _amount: type(uint256).max});
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
    }

    function test_RecursiveSplitBeforeStart() public {
        IGovNFT.Lock memory lock = govNFT.locks(from);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.totalLocked, govNFT.locked(from)); // no tokens have been vested before splitting
        assertEq(lock.splitCount, 0);
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked);

        vm.expectEmit(address(govNFT));
        emit IGovNFT.Split({
            from: from,
            to: from + 1,
            recipient: address(recipient),
            splitAmount1: lock.totalLocked - amount,
            splitAmount2: amount,
            startTime: lock.start,
            endTime: lock.end,
            description: ""
        });
        vm.expectEmit(address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount,
            start: uint40(block.timestamp),
            end: uint40(block.timestamp) + 3 * WEEK,
            cliff: WEEK,
            description: ""
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

        vm.expectEmit(address(govNFT));
        emit IGovNFT.Split({
            from: tokenId,
            to: tokenId + 1,
            recipient: address(recipient2),
            splitAmount1: lock.totalLocked - amount / 2,
            splitAmount2: amount / 2,
            startTime: lock.start,
            endTime: lock.end,
            description: ""
        });
        vm.expectEmit(address(govNFT));
        emit IERC4906.MetadataUpdate(tokenId);
        vm.prank(address(recipient));
        paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount / 2,
            start: uint40(block.timestamp),
            end: uint40(block.timestamp) + 3 * WEEK,
            cliff: WEEK,
            description: ""
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
        uint40 remainingCliff = (lock.start + lock.cliffLength) - uint40(block.timestamp);
        assertEq(remainingCliff, WEEK - 2 days);

        vm.expectEmit(address(govNFT));
        emit IGovNFT.Split({
            from: from,
            to: from + 1,
            recipient: address(recipient),
            splitAmount1: lock.totalLocked - amount,
            splitAmount2: amount,
            startTime: uint40(block.timestamp),
            endTime: lock.end,
            description: ""
        });
        vm.expectEmit(address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: remainingCliff,
            description: ""
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];

        // original NFT assertions
        // since still on cliff and vesting has started, the lock timestamps remain the same
        _checkLockUpdates(from, lock.totalLocked - amount, lock.totalLocked, lock.cliffLength, lock.start, lock.end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient), 0, 1);

        // split NFT assertions
        _checkLockUpdates(tokenId, amount, amount, remainingCliff, uint40(block.timestamp), lock.end);

        // second split assertions
        skip(2 days); // skip somewhere before cliff ends

        lock = govNFT.locks(tokenId);

        assertEq(lock.totalLocked, govNFT.locked(tokenId)); // still on cliff, no tokens vested
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.splitCount, 0);
        remainingCliff = (lock.start + lock.cliffLength) - uint40(block.timestamp);
        assertEq(remainingCliff, WEEK - 4 days);

        vm.expectEmit(address(govNFT));
        emit IGovNFT.Split({
            from: tokenId,
            to: tokenId + 1,
            recipient: address(recipient2),
            splitAmount1: lock.totalLocked - amount / 2,
            splitAmount2: amount / 2,
            startTime: uint40(block.timestamp),
            endTime: lock.end,
            description: ""
        });
        vm.expectEmit(address(govNFT));
        emit IERC4906.MetadataUpdate(tokenId);
        vm.prank(address(recipient));
        paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount / 2,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: remainingCliff,
            description: ""
        });
        uint256 tokenId2 = govNFT.split(tokenId, paramsList)[0];

        // original NFT assertions
        // since still on cliff and vesting has started, the lock timestamps remain the same
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
        _checkLockUpdates(tokenId2, amount / 2, amount / 2, remainingCliff, uint40(block.timestamp), lock.end);
    }

    function test_RecursiveSplitAfterCliffEnd() public {
        skip(WEEK + 2 days); // skip somewhere after cliff ends

        IGovNFT.Lock memory lock = govNFT.locks(from);
        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.splitCount, 0);

        vm.expectEmit(address(govNFT));
        emit IGovNFT.Split({
            from: from,
            to: from + 1,
            recipient: address(recipient),
            splitAmount1: lockedBeforeSplit - amount,
            splitAmount2: amount,
            startTime: uint40(block.timestamp),
            endTime: lock.end,
            description: ""
        });
        vm.expectEmit(address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: amount,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: 0,
            description: ""
        });
        uint256 tokenId = govNFT.split(from, paramsList)[0];

        assertEq(lock.totalLocked, govNFT.locked(from) + govNFT.locked(tokenId) + originalUnclaimed);

        // original NFT assertions
        // no cliff since vesting has already started
        _checkLockUpdates(from, lockedBeforeSplit - amount, lock.totalLocked, 0, uint40(block.timestamp), lock.end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient), originalUnclaimed, 1);
        assertEq(govNFT.locked(from), govNFT.locks(from).totalLocked);

        // split NFT assertions
        // no cliff since vesting has already started
        _checkLockUpdates(tokenId, amount, amount, 0, uint40(block.timestamp), lock.end);
        assertEq(govNFT.locked(tokenId), govNFT.locks(tokenId).totalLocked);

        // second split checks
        skip(2 days);

        lock = govNFT.locks(tokenId);

        lockedBeforeSplit = govNFT.locked(tokenId);
        originalUnclaimed = govNFT.unclaimed(tokenId);
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked);
        assertEq(lock.unclaimedBeforeSplit, 0);
        assertEq(lock.splitCount, 0);

        vm.expectEmit(address(govNFT));
        emit IGovNFT.Split({
            from: tokenId,
            to: tokenId + 1,
            recipient: address(recipient2),
            splitAmount1: lockedBeforeSplit - amount / 2,
            splitAmount2: amount / 2,
            startTime: uint40(block.timestamp),
            endTime: lock.end,
            description: ""
        });
        vm.expectEmit(address(govNFT));
        emit IERC4906.MetadataUpdate(tokenId);
        vm.prank(address(recipient));
        paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount / 2,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: 0,
            description: ""
        });
        uint256 tokenId2 = govNFT.split(tokenId, paramsList)[0];

        assertEq(lock.totalLocked, govNFT.locked(tokenId) + govNFT.locked(tokenId2) + originalUnclaimed);

        // original NFT assertions
        // no cliff since vesting has already started
        _checkLockUpdates(
            tokenId,
            lockedBeforeSplit - amount / 2,
            lock.totalLocked,
            0,
            uint40(block.timestamp),
            lock.end
        );
        _checkSplitInfo(tokenId, tokenId2, address(recipient), address(recipient2), originalUnclaimed, 1);
        assertEq(govNFT.locked(tokenId), govNFT.locks(tokenId).totalLocked);

        // split NFT assertions
        // no cliff since vesting has already started
        _checkLockUpdates(tokenId2, amount / 2, amount / 2, 0, uint40(block.timestamp), lock.end);
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
        vm.expectEmit(address(govNFT));
        emit IGovNFT.Split({
            from: from,
            to: from + 1,
            recipient: approvedUser,
            splitAmount1: lock.totalLocked - TOKEN_1,
            splitAmount2: TOKEN_1,
            startTime: lock.start,
            endTime: lock.end,
            description: ""
        });
        vm.expectEmit(address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: approvedUser,
            amount: TOKEN_1,
            start: uint40(block.timestamp),
            end: uint40(block.timestamp) + 3 * WEEK,
            cliff: WEEK,
            description: ""
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
        vm.expectEmit(address(govNFT));
        emit IGovNFT.Split({
            from: from,
            to: tokenId + 1,
            recipient: approvedForAllUser,
            splitAmount1: lock.totalLocked - TOKEN_1 * 2,
            splitAmount2: TOKEN_1,
            startTime: lock.start,
            endTime: lock.end,
            description: ""
        });
        vm.expectEmit(address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: approvedForAllUser,
            amount: TOKEN_1,
            start: uint40(block.timestamp),
            end: uint40(block.timestamp) + 3 * WEEK,
            cliff: WEEK,
            description: ""
        });
        uint256 tokenId2 = govNFT.split(from, paramsList)[0];

        assertEq(govNFT.ownerOf(tokenId2), approvedForAllUser);
        assertEq(govNFT.balanceOf(approvedForAllUser), 1);
        // split updates minter in child lock
        assertEq(govNFT.locks(tokenId2).minter, approvedForAllUser);
    }

    function test_RevertIf_SplitNonExistentToken() public {
        uint256 tokenId = from + 2;
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
        vm.prank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: TOKEN_1,
            start: uint40(block.timestamp),
            end: uint40(block.timestamp) + 3 * WEEK,
            cliff: WEEK,
            description: ""
        });
        govNFT.split(tokenId, paramsList);
    }

    function test_RevertIf_SplitWhenVestingIsFinished() public {
        skip(WEEK * 3);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.AmountTooBig.selector);
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: uint40(block.timestamp),
            end: uint40(block.timestamp) + WEEK * 3,
            cliff: WEEK,
            description: ""
        });
        govNFT.split(from, paramsList);
    }

    function test_SplitToUpdatesTimestamps() public {
        IGovNFT.Lock memory lock = govNFT.locks(from);

        vm.prank(address(recipient));
        vm.expectEmit(address(govNFT));
        emit IGovNFT.Split({
            from: from,
            to: from + 1,
            recipient: address(recipient2),
            splitAmount1: lock.totalLocked - amount,
            splitAmount2: amount,
            startTime: lock.start + WEEK,
            endTime: lock.end + WEEK,
            description: ""
        });
        vm.expectEmit(address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start + WEEK,
            end: lock.end + WEEK,
            cliff: lock.cliffLength + WEEK,
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

        assertEq(splitLock.end, lock.end + WEEK);
        assertEq(splitLock.start, lock.start + WEEK);
        assertEq(splitLock.cliffLength, lock.cliffLength + WEEK);
        assertEq(govNFT.ownerOf(tokenId), address(recipient2));

        skip(lock.end); // skips to end of tokenId1 vesting
        // vesting is finished for token1
        assertEq(govNFT.unclaimed(from), lock.totalLocked - amount);
        assertEq(govNFT.locked(from), 0);

        vm.prank(address(recipient));
        govNFT.claim({_tokenId: from, _beneficiary: address(recipient), _amount: lock.totalLocked});
        assertEq(IERC20(testToken).balanceOf(address(recipient)), lock.totalLocked - amount);

        // vesting is not finished for token2
        assertLt(govNFT.unclaimed(tokenId), amount);
        assertGt(govNFT.locked(tokenId), 0);

        skip(splitLock.end); // skips to end of tokenId vesting
        // vesting is finished for token2
        assertEq(govNFT.unclaimed(tokenId), amount);
        assertEq(govNFT.locked(tokenId), 0);

        vm.prank(address(recipient2));
        govNFT.claim({_tokenId: tokenId, _beneficiary: address(recipient2), _amount: lock.totalLocked});
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), amount);
    }
}
