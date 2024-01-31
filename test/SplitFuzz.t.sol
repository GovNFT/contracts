// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

import "src/GovNFT.sol";
import "forge-std/console.sol";

contract SplitFuzzTest is BaseTest {
    event Split(
        uint256 indexed _from,
        uint256 indexed _tokenId,
        address _recipient,
        uint256 _splitAmount1,
        uint256 _splitAmount2,
        uint256 _startTime,
        uint256 _endTime
    );

    function testFuzzSplitBeforeStart(uint128 lockAmount, uint256 amount, uint32 _timeskip) public {
        vm.assume(lockAmount > 2);
        uint256 timeskip = uint256(_timeskip);
        timeskip = bound(timeskip, 0, WEEK * 2);
        amount = bound(amount, 1, uint256(lockAmount) - 1); // amount to split has to be lower than lock
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
        (
            uint256 totalLocked,
            ,
            uint256 splitCount,
            uint256 unclaimedBeforeSplit,
            ,
            uint256 cliffLength,
            uint256 start,
            uint256 end,
            ,
            ,

        ) = govNFT.locks(from);
        assertEq(unclaimedBeforeSplit, 0);
        assertEq(totalLocked, govNFT.locked(from)); // no tokens have been vested before splitting
        assertEq(splitCount, 0);

        skip(timeskip);

        vm.expectEmit(true, true, false, true);
        emit Split(from, from + 1, address(recipient2), totalLocked - amount, amount, start, end);
        vm.prank(address(recipient));
        uint256 tokenId = govNFT.split(address(recipient2), from, amount, start, end, WEEK);

        // original NFT assertions
        // start timestamps and cliffs remain the same as parent token, since vesting has not started
        _checkLockUpdates(from, totalLocked - amount, totalLocked, cliffLength, start, end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), 0, 1);

        // split NFT assertions
        // start timestamps and cliffs remain the same as parent token
        _checkLockUpdates(tokenId, amount, amount, cliffLength, start, end);
    }

    function testFuzzSplitClaimsBeforeStart(uint128 lockAmount, uint256 amount, uint32 _timeskip) public {
        vm.assume(lockAmount > 2);
        uint256 timeskip = uint256(_timeskip);
        timeskip = bound(timeskip, 0, WEEK * 2);
        amount = bound(amount, 1, uint256(lockAmount) - 1); // amount to split has to be lower than lock
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
        {
            (, , , uint256 unclaimedBeforeSplit, uint256 splitCount, , , , , , ) = govNFT.locks(from);
            assertEq(unclaimedBeforeSplit, 0);
            assertEq(splitCount, 0);
        }

        (uint256 totalLocked, , , , , , uint256 start, uint256 end, , , ) = govNFT.locks(from);
        assertEq(totalLocked, govNFT.locked(from)); // no tokens have been vested before splitting

        skip(timeskip);

        vm.expectEmit(true, true, false, true);
        emit Split(from, from + 1, address(recipient2), totalLocked - amount, amount, start, end);
        vm.prank(address(recipient));
        uint256 tokenId = govNFT.split(address(recipient2), from, amount, start, end, WEEK);
        _checkLockedUnclaimedSplit(from, totalLocked - amount, 0, tokenId, amount, 0);

        // split NFT assertions
        (, , , , , , , uint256 endSplit, , , ) = govNFT.locks(tokenId);
        skip(endSplit - block.timestamp);

        _checkLockedUnclaimedSplit(from, 0, totalLocked - amount, tokenId, 0, amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        vm.prank(address(recipient));
        govNFT.claim(from, address(recipient), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), totalLocked - amount);

        vm.prank(address(recipient2));
        govNFT.claim(tokenId, address(recipient2), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), amount);
    }

    function testFuzzSplitBeforeCliffEnd(uint128 lockAmount, uint256 amount, uint32 _timeskip) public {
        vm.assume(lockAmount > 2);
        uint256 timeskip = uint256(_timeskip);
        timeskip = bound(timeskip, 0, WEEK * 3 - 1);
        amount = bound(amount, 1, uint256(lockAmount) - 1); // amount to split has to be lower than lock
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

        (
            uint256 totalLocked,
            ,
            ,
            uint256 unclaimedBeforeSplit,
            uint256 splitCount,
            uint256 cliffLength,
            uint256 start,
            uint256 end,
            ,
            ,

        ) = govNFT.locks(from);
        assertEq(unclaimedBeforeSplit, 0);
        assertEq(totalLocked, govNFT.locked(from)); // still on cliff, no tokens vested
        assertEq(splitCount, 0);

        vm.expectEmit(true, true, false, true);
        emit Split(from, from + 1, address(recipient2), totalLocked - amount, amount, block.timestamp, end);
        vm.prank(address(recipient));
        uint256 tokenId = govNFT.split(address(recipient2), from, amount, block.timestamp, end, cliffLength - timeskip);

        // original NFT assertions
        uint256 remainingCliff = (start + cliffLength) - block.timestamp;
        _checkLockUpdates(from, totalLocked - amount, totalLocked, remainingCliff, block.timestamp, end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), 0, 1);
        assertEq(remainingCliff, cliffLength - timeskip);

        // split NFT assertions
        _checkLockUpdates(tokenId, amount, amount, remainingCliff, block.timestamp, end);
    }

    function testFuzzSplitClaimsBeforeCliffEnd(uint128 lockAmount, uint256 amount, uint32 _timeskip) public {
        vm.assume(lockAmount > 2);
        uint256 timeskip = uint256(_timeskip);
        timeskip = bound(timeskip, 0, WEEK * 3 - 1);
        amount = bound(amount, 1, uint256(lockAmount) - 1); // amount to split has to be lower than lock
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

        (uint256 totalLocked, , , uint256 unclaimedBeforeSplit, uint256 splitCount, , , uint256 end, , , ) = govNFT
            .locks(from);
        assertEq(unclaimedBeforeSplit, 0);
        assertEq(totalLocked, govNFT.locked(from)); // still on cliff, no tokens vested
        assertEq(splitCount, 0);

        vm.expectEmit(true, true, false, true);
        emit Split(from, from + 1, address(recipient2), totalLocked - amount, amount, block.timestamp, end);
        vm.prank(address(recipient));
        uint256 tokenId = govNFT.split(address(recipient2), from, amount, block.timestamp, end, WEEK * 3 - timeskip);
        _checkLockedUnclaimedSplit(from, totalLocked - amount, 0, tokenId, amount, 0);

        (, , , , , , , uint256 endSplit, , , ) = govNFT.locks(tokenId);
        skip(endSplit - block.timestamp);

        _checkLockedUnclaimedSplit(from, 0, totalLocked - amount, tokenId, 0, amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        vm.prank(address(recipient));
        govNFT.claim(from, address(recipient), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), totalLocked - amount);

        vm.prank(address(recipient2));
        govNFT.claim(tokenId, address(recipient2), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), amount);
    }

    function testFuzzSplitAfterCliffEnd(uint128 lockAmount, uint256 amount, uint32 _timeskip) public {
        vm.assume(lockAmount > 3); // to avoid bound reverts
        uint256 timeskip = uint256(_timeskip);
        timeskip = bound(timeskip, WEEK, WEEK * 6);
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

        (uint256 totalLocked, , , uint256 unclaimedBeforeSplit, uint256 splitCount, , , uint256 end, , , ) = govNFT
            .locks(from);
        assertEq(unclaimedBeforeSplit, 0);
        assertEq(splitCount, 0);
        uint256 lockedBeforeSplit = govNFT.locked(from);
        // can only split if locked is greater than 1
        while (lockedBeforeSplit <= 1) {
            rewind(1 days);
            lockedBeforeSplit = govNFT.locked(from);
        }
        unclaimedBeforeSplit = govNFT.unclaimed(from);
        amount = bound(amount, 1, lockedBeforeSplit - 1); // amount to split has to be lower than locked value

        vm.expectEmit(true, true, false, true);
        emit Split(from, from + 1, address(recipient2), lockedBeforeSplit - amount, amount, block.timestamp, end);
        vm.prank(address(recipient));
        uint256 tokenId = govNFT.split(address(recipient2), from, amount, block.timestamp, end, 0);

        // unclaimed and locked remain untouched
        assertEq(lockedBeforeSplit + unclaimedBeforeSplit, uint256(lockAmount));
        assertEq(govNFT.locked(from), lockedBeforeSplit - amount);
        assertEq(govNFT.unclaimed(from), unclaimedBeforeSplit);

        // original NFT assertions
        (uint256 totalLockedSplit, , , , , , , , , , ) = govNFT.locks(from);
        // no cliff since vesting has already started
        _checkLockUpdates(from, lockedBeforeSplit - amount, totalLocked, 0, block.timestamp, end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), unclaimedBeforeSplit, 1);
        assertEq(govNFT.locked(from), totalLockedSplit);

        // split NFT assertions
        (totalLockedSplit, , , , , , , , , , ) = govNFT.locks(tokenId);
        assertEq(govNFT.locked(tokenId), totalLockedSplit);

        // no cliff since vesting has already started
        _checkLockUpdates(tokenId, amount, amount, 0, block.timestamp, end);
    }

    function testFuzzSplitClaimsAfterCliffEnd(uint128 lockAmount, uint256 amount, uint32 _timeskip) public {
        vm.assume(lockAmount > 3); // to avoid bound reverts
        uint256 timeskip = uint256(_timeskip);
        timeskip = bound(timeskip, WEEK, WEEK * 6);
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

        (, , , uint256 unclaimedBeforeSplit, uint256 splitCount, , , uint256 end, , , ) = govNFT.locks(from);
        assertEq(unclaimedBeforeSplit, 0);
        assertEq(splitCount, 0);
        uint256 lockedBeforeSplit = govNFT.locked(from);
        // can only split if locked is greater than 1
        while (lockedBeforeSplit <= 1) {
            rewind(1 days);
            lockedBeforeSplit = govNFT.locked(from);
        }
        unclaimedBeforeSplit = govNFT.unclaimed(from);
        amount = bound(amount, 1, lockedBeforeSplit - 1); // amount to split has to be lower than locked value

        vm.expectEmit(true, true, false, true);
        emit Split(from, from + 1, address(recipient2), lockedBeforeSplit - amount, amount, block.timestamp, end);
        vm.prank(address(recipient));
        uint256 tokenId = govNFT.split(address(recipient2), from, amount, block.timestamp, end, 0);
        _checkLockedUnclaimedSplit(from, lockedBeforeSplit - amount, unclaimedBeforeSplit, tokenId, amount, 0);

        (, , , , , , , uint256 endSplit, , , ) = govNFT.locks(tokenId);
        skip(endSplit - block.timestamp);

        _checkLockedUnclaimedSplit(from, 0, unclaimedBeforeSplit + lockedBeforeSplit - amount, tokenId, 0, amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        vm.prank(address(recipient2));
        govNFT.claim(tokenId, address(recipient2), lockAmount);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), amount);

        vm.prank(address(recipient));
        govNFT.claim(from, address(recipient), lockAmount);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), lockedBeforeSplit + unclaimedBeforeSplit - amount);
    }

    function testFuzzSplitClaimsAtSplitTimestampAfterCliffEnd(
        uint128 lockAmount,
        uint256 amount,
        uint32 _timeskip
    ) public {
        vm.assume(lockAmount > 3); // to avoid bound reverts
        uint256 timeskip = uint256(_timeskip);
        timeskip = bound(timeskip, WEEK, WEEK * 6);
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

        (, , , uint256 unclaimedBeforeSplit, uint256 splitCount, , , uint256 end, , , ) = govNFT.locks(from);
        assertEq(unclaimedBeforeSplit, 0);
        assertEq(splitCount, 0);
        uint256 lockedBeforeSplit = govNFT.locked(from);
        // can only split if locked is greater than 1
        while (lockedBeforeSplit <= 1) {
            rewind(1 days);
            lockedBeforeSplit = govNFT.locked(from);
        }
        unclaimedBeforeSplit = govNFT.unclaimed(from);
        amount = bound(amount, 1, lockedBeforeSplit - 1); // amount to split has to be lower than locked value

        vm.expectEmit(true, true, false, true);
        emit Split(from, from + 1, address(recipient2), lockedBeforeSplit - amount, amount, block.timestamp, end);
        vm.prank(address(recipient));
        uint256 tokenId = govNFT.split(address(recipient2), from, amount, block.timestamp, end, 0);
        _checkLockedUnclaimedSplit(from, lockedBeforeSplit - amount, unclaimedBeforeSplit, tokenId, amount, 0);

        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        // nothing to claim on split token in split timestamp
        vm.prank(address(recipient2));
        govNFT.claim(tokenId, address(recipient2), lockAmount);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        (, , uint256 totalClaimed, , , , , , , , ) = govNFT.locks(tokenId);
        assertEq(totalClaimed, 0);

        vm.prank(address(recipient));
        govNFT.claim(from, address(recipient), lockAmount);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), unclaimedBeforeSplit);
        (, , totalClaimed, , , , , , , , ) = govNFT.locks(from);
        assertEq(totalClaimed, 0); // unclaimed before split not included
    }
}
