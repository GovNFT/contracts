// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import {IERC721Errors} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";

import {stdStorage, StdStorage} from "forge-std/Test.sol";

import "test/utils/BaseTest.sol";

import "src/GovNFT.sol";

contract SplitTest is BaseTest {
    using stdStorage for StdStorage;

    event Split(
        uint256 indexed from,
        uint256 indexed tokenId,
        address recipient,
        uint256 splitAmount1,
        uint256 splitAmount2,
        uint256 startTime,
        uint256 endTime
    );

    uint256 from;
    uint256 from1;
    uint256 amount;

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

        admin1.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin1));
        from1 = govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp + WEEK,
            block.timestamp + WEEK * 4,
            WEEK * 2
        );
    }

    function testSplitBeforeStart() public {
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
            address vault,

        ) = govNFT.locks(from);
        assertEq(unclaimedBeforeSplit, 0);
        assertEq(totalLocked, govNFT.locked(from)); // no tokens have been vested before splitting
        assertEq(splitCount, 0);
        assertEq(IERC20(testToken).balanceOf(vault), totalLocked);

        vm.expectEmit(true, true, false, true);
        emit Split(from, from + 2, address(recipient2), totalLocked - amount, amount, start, end);
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        uint256 tokenId = govNFT.split(address(recipient2), from, amount, start, end, cliffLength);

        // original NFT assertions
        // start timestamps and cliffs remain the same as parent token, since vesting has not started
        _checkLockUpdates(from, totalLocked - amount, totalLocked, cliffLength, start, end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), 0, 1);

        // split NFT assertions
        // start timestamps and cliffs remain the same as parent token
        _checkLockUpdates(tokenId, amount, amount, cliffLength, start, end);
    }

    function testSplitClaimsBeforeStart() public {
        (uint256 totalLocked, , uint256 totalClaimed, , , , uint256 start, uint256 end, , , ) = govNFT.locks(from);
        assertEq(totalClaimed, 0);

        vm.expectEmit(true, true, false, true);
        emit Split(from, from + 2, address(recipient2), totalLocked - amount, amount, start, end);
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        uint256 tokenId = govNFT.split(address(recipient2), from, amount, start, end, WEEK);

        (, , , , , , , uint256 endSplit, , , ) = govNFT.locks(tokenId);

        _checkLockedUnclaimedSplit(from, totalLocked - amount, 0, tokenId, amount, 0);

        skip(endSplit - block.timestamp);

        _checkLockedUnclaimedSplit(from, 0, totalLocked - amount, tokenId, 0, amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        (, , totalClaimed, , , , , , , , ) = govNFT.locks(from);
        // assert claims
        assertEq(totalClaimed, 0);
        vm.prank(address(recipient));
        govNFT.claim(from, address(recipient), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), totalLocked - amount);
        (, , totalClaimed, , , , , , , , ) = govNFT.locks(from);
        assertEq(totalClaimed, totalLocked - amount);

        (, , totalClaimed, , , , , , , , ) = govNFT.locks(tokenId);
        assertEq(totalClaimed, 0);
        vm.prank(address(recipient2));
        govNFT.claim(tokenId, address(recipient2), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), amount);
        (, , totalClaimed, , , , , , , , ) = govNFT.locks(tokenId);
        assertEq(totalClaimed, amount);
    }

    function testSplitBeforeCliffEnd() public {
        skip(5 days); // skip somewhere before cliff ends

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
            address vault,

        ) = govNFT.locks(from);
        assertEq(unclaimedBeforeSplit, 0);
        assertEq(totalLocked, govNFT.locked(from)); // still on cliff, no tokens vested
        assertEq(splitCount, 0);
        assertEq(IERC20(testToken).balanceOf(vault), totalLocked);

        vm.expectEmit(true, true, false, true);
        emit Split(from, from + 2, address(recipient2), totalLocked - amount, amount, block.timestamp, end);
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        uint256 tokenId = govNFT.split(address(recipient2), from, amount, block.timestamp, end, WEEK - 5 days);

        // original NFT assertions
        uint256 remainingCliff = (start + cliffLength) - block.timestamp;
        // since still on cliff and vesting has started, the split cliff length will be
        // the remaining cliff period and the new start will be the current timestamp
        _checkLockUpdates(from, totalLocked - amount, totalLocked, remainingCliff, block.timestamp, end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), 0, 1);
        assertEq(remainingCliff, WEEK - 5 days);

        // split NFT assertions
        _checkLockUpdates(tokenId, amount, amount, remainingCliff, block.timestamp, end);
    }

    function testSplitClaimsBeforeCliffEnd() public {
        skip(5 days); // skip somewhere before cliff ends

        (uint256 totalLocked, , uint256 totalClaimed, , , , , uint256 end, , , ) = govNFT.locks(from);
        assertEq(totalClaimed, 0);

        vm.expectEmit(true, true, false, true);
        emit Split(from, from + 2, address(recipient2), totalLocked - amount, amount, block.timestamp, end);
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        uint256 tokenId = govNFT.split(address(recipient2), from, amount, block.timestamp, end, WEEK - 5 days);

        (, , , , , , , uint256 endSplit, , , ) = govNFT.locks(tokenId);

        _checkLockedUnclaimedSplit(from, totalLocked - amount, 0, tokenId, amount, 0);

        skip(endSplit - block.timestamp);

        _checkLockedUnclaimedSplit(from, 0, totalLocked - amount, tokenId, 0, amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        (, , totalClaimed, , , , , , , , ) = govNFT.locks(from);
        // assert claims
        assertEq(totalClaimed, 0);
        vm.prank(address(recipient));
        govNFT.claim(from, address(recipient), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), totalLocked - amount);
        (, , totalClaimed, , , , , , , , ) = govNFT.locks(from);
        assertEq(totalClaimed, totalLocked - amount);

        (, , totalClaimed, , , , , , , , ) = govNFT.locks(tokenId);
        assertEq(totalClaimed, 0);
        vm.prank(address(recipient2));
        govNFT.claim(tokenId, address(recipient2), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), amount);
        (, , totalClaimed, , , , , , , , ) = govNFT.locks(tokenId);
        assertEq(totalClaimed, amount);
    }

    function testSplitAfterCliffEnd() public {
        skip(WEEK + 2 days); // skip somewhere after cliff ends

        (
            uint256 totalLocked,
            ,
            ,
            uint256 unclaimedBeforeSplit,
            uint256 splitCount,
            ,
            ,
            uint256 end,
            ,
            address vault,

        ) = govNFT.locks(from);
        assertEq(unclaimedBeforeSplit, 0);
        assertEq(splitCount, 0);
        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);
        assertEq(IERC20(testToken).balanceOf(vault), totalLocked);

        vm.expectEmit(true, true, false, true);
        emit Split(from, from + 2, address(recipient2), lockedBeforeSplit - amount, amount, block.timestamp, end);
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        uint256 tokenId = govNFT.split(address(recipient2), from, amount, block.timestamp, end, 0);

        assertEq(totalLocked, govNFT.locked(from) + govNFT.locked(tokenId) + originalUnclaimed);

        // original NFT assertions
        (uint256 totalLockedSplit, , , , , , , , , , ) = govNFT.locks(from);

        // no cliff since vesting has already started
        _checkLockUpdates(from, lockedBeforeSplit - amount, totalLocked, 0, block.timestamp, end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), originalUnclaimed, 1);
        assertEq(govNFT.locked(from), totalLockedSplit);

        // split NFT assertions
        (totalLockedSplit, , , , , , , , , , ) = govNFT.locks(tokenId);

        // no cliff since vesting has already started
        _checkLockUpdates(tokenId, amount, amount, 0, block.timestamp, end);

        assertEq(govNFT.locked(tokenId), totalLockedSplit);
    }

    function testSplitAfterCliffEndAndClaim() public {
        skip(WEEK + 2 days); // skip somewhere after cliff ends

        (
            uint256 totalLocked,
            ,
            ,
            uint256 unclaimedBeforeSplit,
            uint256 splitCount,
            ,
            ,
            uint256 end,
            ,
            address vault,

        ) = govNFT.locks(from);
        assertEq(unclaimedBeforeSplit, 0);
        assertEq(splitCount, 0);

        vm.prank(address(recipient));
        govNFT.claim(from, address(recipient), totalLocked);
        (, , uint256 totalClaimed, , , , , , , , ) = govNFT.locks(from);

        skip(2 days); // skip somewhere before vesting ends to vest more rewards
        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);
        assertEq(IERC20(testToken).balanceOf(vault), totalLocked - totalClaimed);

        vm.expectEmit(true, true, false, true);
        emit Split(from, from + 2, address(recipient2), lockedBeforeSplit - amount, amount, block.timestamp, end);
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        uint256 tokenId = govNFT.split(address(recipient2), from, amount, block.timestamp, end, 0);

        assertEq(totalLocked, govNFT.locked(from) + govNFT.locked(tokenId) + originalUnclaimed + totalClaimed);

        // original NFT assertions
        (uint256 totalLockedSplit, , , , , , , , , , ) = govNFT.locks(from);

        // no cliff since vesting has already started
        _checkLockUpdates(from, lockedBeforeSplit - amount, totalLocked, 0, block.timestamp, end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), originalUnclaimed, 1);
        assertEq(govNFT.locked(from), totalLockedSplit);

        // split NFT assertions
        (totalLockedSplit, , , , , , , , , , ) = govNFT.locks(tokenId);

        // no cliff since vesting has already started
        _checkLockUpdates(tokenId, amount, amount, 0, block.timestamp, end);
        assertEq(govNFT.locked(tokenId), totalLockedSplit);
    }

    function testSplitClaimsWithUnclaimedRewardsAfterCliffEnd() public {
        skip(WEEK + 2 days); // skip somewhere after cliff ends

        (uint256 totalLocked, , uint256 totalClaimed, uint256 unclaimedBeforeSplit, , , , uint256 end, , , ) = govNFT
            .locks(from);
        assertEq(unclaimedBeforeSplit, 0);
        assertEq(totalClaimed, 0);
        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);

        vm.expectEmit(true, true, false, true);
        emit Split(from, from + 2, address(recipient2), lockedBeforeSplit - amount, amount, block.timestamp, end);
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        uint256 tokenId = govNFT.split(address(recipient2), from, amount, block.timestamp, end, WEEK);

        // previous unclaimed tokens are stored
        (, , uint256 newTotalClaimed, uint256 newUnclaimedBeforeSplit, , , , , , , ) = govNFT.locks(from);
        assertEq(newUnclaimedBeforeSplit, originalUnclaimed);
        assertEq(newTotalClaimed, 0);

        (, , newTotalClaimed, newUnclaimedBeforeSplit, , , , , , , ) = govNFT.locks(tokenId);
        assertEq(newUnclaimedBeforeSplit, 0);
        assertEq(newTotalClaimed, 0);

        // the only amount claimable is the originalUnclaimed
        assertEq(totalLocked, lockedBeforeSplit + originalUnclaimed);

        (, , , , , , , uint256 endSplit, , , ) = govNFT.locks(tokenId);

        _checkLockedUnclaimedSplit(from, lockedBeforeSplit - amount, originalUnclaimed, tokenId, amount, 0);

        skip(endSplit - block.timestamp);

        _checkLockedUnclaimedSplit(from, 0, originalUnclaimed + lockedBeforeSplit - amount, tokenId, 0, amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        // assert claims
        vm.prank(address(recipient));
        govNFT.claim(from, address(recipient), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), originalUnclaimed + lockedBeforeSplit - amount);
        (, , totalClaimed, , , , , , , , ) = govNFT.locks(from);
        assertEq(totalClaimed, lockedBeforeSplit - amount); //unclaimed before split not included

        vm.prank(address(recipient2));
        govNFT.claim(tokenId, address(recipient2), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), amount);
        (, , totalClaimed, , , , , , , , ) = govNFT.locks(tokenId);
        assertEq(totalClaimed, amount);
    }

    function testSplitClaimsAtSplitTimestampWithUnclaimedRewardsAfterCliffEnd() public {
        skip(WEEK + 2 days); // skip somewhere after cliff ends

        (uint256 totalLocked, , uint256 totalClaimed, uint256 unclaimedBeforeSplit, , , , uint256 end, , , ) = govNFT
            .locks(from);
        assertEq(unclaimedBeforeSplit, 0);
        assertEq(totalClaimed, 0);
        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);

        vm.expectEmit(true, true, false, true);
        emit Split(from, from + 2, address(recipient2), lockedBeforeSplit - amount, amount, block.timestamp, end);
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        uint256 tokenId = govNFT.split(address(recipient2), from, amount, block.timestamp, end, WEEK);

        // previous unclaimed tokens are stored
        (, , uint256 newTotalClaimed, uint256 newUnclaimedBeforeSplit, , , , , , , ) = govNFT.locks(from);
        assertEq(newUnclaimedBeforeSplit, originalUnclaimed);
        assertEq(newTotalClaimed, 0);

        (, , newTotalClaimed, newUnclaimedBeforeSplit, , , , , , , ) = govNFT.locks(tokenId);
        assertEq(newUnclaimedBeforeSplit, 0);
        assertEq(newTotalClaimed, 0);

        // the only amount claimable is the originalUnclaimed
        assertEq(totalLocked, lockedBeforeSplit + originalUnclaimed);

        _checkLockedUnclaimedSplit(from, lockedBeforeSplit - amount, originalUnclaimed, tokenId, amount, 0);

        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        // assert claims
        vm.prank(address(recipient));
        govNFT.claim(from, address(recipient), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), originalUnclaimed);
        (, , totalClaimed, , , , , , , , ) = govNFT.locks(from);
        assertEq(totalClaimed, 0); // unclaimed before split not included

        // nothing to claim on split token in split timestamp
        vm.prank(address(recipient2));
        govNFT.claim(tokenId, address(recipient2), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        (, , totalClaimed, , , , , , , , ) = govNFT.locks(tokenId);
        assertEq(totalClaimed, 0);
    }

    function testSplitClaimsWithClaimedRewardsAfterCliffEnd() public {
        skip(WEEK + 2 days); // skip somewhere after cliff ends

        (uint256 totalLocked, , uint256 totalClaimed, uint256 unclaimedBeforeSplit, , , , uint256 end, , , ) = govNFT
            .locks(from);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);
        assertEq(unclaimedBeforeSplit, 0);
        assertEq(totalClaimed, 0);
        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);

        vm.prank(address(recipient));
        govNFT.claim(from, address(recipient), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), originalUnclaimed);
        (, , totalClaimed, , , , , , , , ) = govNFT.locks(from);
        assertEq(totalClaimed, originalUnclaimed);
        assertEq(govNFT.unclaimed(from), 0);

        vm.expectEmit(true, true, false, true);
        emit Split(from, from + 2, address(recipient2), lockedBeforeSplit - amount, amount, block.timestamp, end);
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        uint256 tokenId = govNFT.split(address(recipient2), from, amount, block.timestamp, end, WEEK);

        // previous totalClaimed was reset and no rewards were left unclaimed
        (, , totalClaimed, unclaimedBeforeSplit, , , , , , , ) = govNFT.locks(from);
        assertEq(totalClaimed, 0);
        assertEq(unclaimedBeforeSplit, 0);

        (, , totalClaimed, unclaimedBeforeSplit, , , , , , , ) = govNFT.locks(from);
        assertEq(totalClaimed, 0);
        assertEq(unclaimedBeforeSplit, 0);

        // the only amount claimable is the originalUnclaimed
        assertEq(totalLocked, lockedBeforeSplit + originalUnclaimed);

        (, , , , , , , uint256 endSplit, , , ) = govNFT.locks(tokenId);

        _checkLockedUnclaimedSplit(from, lockedBeforeSplit - amount, 0, tokenId, amount, 0);

        skip(endSplit - block.timestamp);

        _checkLockedUnclaimedSplit(from, 0, lockedBeforeSplit - amount, tokenId, 0, amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), originalUnclaimed);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);

        // assert claims
        vm.prank(address(recipient));
        govNFT.claim(from, address(recipient), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), originalUnclaimed + lockedBeforeSplit - amount);
        (, , totalClaimed, , , , , , , , ) = govNFT.locks(from);
        assertEq(totalClaimed, lockedBeforeSplit - amount); //unclaimed before split not included

        vm.prank(address(recipient2));
        govNFT.claim(tokenId, address(recipient2), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), amount);
        (, , totalClaimed, , , , , , , , ) = govNFT.locks(tokenId);
        assertEq(totalClaimed, amount);
    }

    function testRecursiveSplitBeforeStart() public {
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
            address vault,

        ) = govNFT.locks(from);
        assertEq(unclaimedBeforeSplit, 0);
        assertEq(totalLocked, govNFT.locked(from)); // no tokens have been vested before splitting
        assertEq(splitCount, 0);
        assertEq(IERC20(testToken).balanceOf(vault), totalLocked);

        vm.expectEmit(true, true, false, true);
        emit Split(from, from + 2, address(recipient), totalLocked - amount, amount, start, end);
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        uint256 tokenId = govNFT.split(
            address(recipient),
            from,
            amount,
            block.timestamp,
            block.timestamp + 3 * WEEK,
            WEEK
        );

        // parent NFT assertions
        // start timestamps and cliffs remain the same as parent token, since vesting has not started
        _checkLockUpdates(from, totalLocked - amount, totalLocked, cliffLength, start, end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient), 0, 1);

        // split NFT assertions
        // start timestamps and cliffs remain the same as parent token
        _checkLockUpdates(tokenId, amount, amount, cliffLength, start, end);

        // second split assertions
        (totalLocked, , , unclaimedBeforeSplit, splitCount, cliffLength, start, end, , vault, ) = govNFT.locks(tokenId);
        assertEq(unclaimedBeforeSplit, 0);
        assertEq(totalLocked, govNFT.locked(tokenId)); // no tokens have been vested before splitting
        assertEq(splitCount, 0);

        vm.expectEmit(true, true, false, true);
        emit Split(tokenId, tokenId + 1, address(recipient2), totalLocked - amount / 2, amount / 2, start, end);
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(tokenId);
        vm.prank(address(recipient));
        uint256 tokenId2 = govNFT.split(
            address(recipient2),
            tokenId,
            amount / 2,
            block.timestamp,
            block.timestamp + 3 * WEEK,
            WEEK
        );

        // parent NFT assertions
        // start timestamps and cliffs remain the same as parent token, since vesting has not started
        _checkLockUpdates(tokenId, totalLocked - amount / 2, totalLocked, cliffLength, start, end);
        _checkSplitInfo(tokenId, tokenId2, address(recipient), address(recipient2), 0, 1);

        // split NFT assertions
        // start timestamps and cliffs remain the same as parent token
        _checkLockUpdates(tokenId2, amount / 2, amount / 2, cliffLength, start, end);
    }

    function testRecursiveSplitBeforeCliffEnd() public {
        skip(2 days); // skip somewhere before cliff ends

        (uint256 totalLocked, , , , , uint256 cliffLength, uint256 start, uint256 end, , address vault, ) = govNFT
            .locks(from);
        assertEq(totalLocked, govNFT.locked(from)); // still on cliff, no tokens vested
        assertEq(IERC20(testToken).balanceOf(vault), totalLocked);

        {
            (, , , uint256 unclaimedBeforeSplit, uint256 splitCount, , , , , , ) = govNFT.locks(from);
            assertEq(unclaimedBeforeSplit, 0);
            assertEq(splitCount, 0);
        }

        vm.expectEmit(true, true, false, true);
        emit Split(from, from + 2, address(recipient), totalLocked - amount, amount, block.timestamp, end);
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        uint256 tokenId = govNFT.split(address(recipient), from, amount, block.timestamp, end, WEEK - 2 days);

        (, , , , , , , , , address splitVault, ) = govNFT.locks(tokenId);

        // original NFT assertions
        uint256 remainingCliff = (start + cliffLength) - block.timestamp;
        // since still on cliff and vesting has started, the split cliff length will be
        // the remaining cliff period and the new start will be the current timestamp
        _checkLockUpdates(from, totalLocked - amount, totalLocked, remainingCliff, block.timestamp, end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient), 0, 1);
        assertEq(remainingCliff, WEEK - 2 days);

        // split NFT assertions
        _checkLockUpdates(tokenId, amount, amount, remainingCliff, block.timestamp, end);

        // second split assertions
        skip(2 days); // skip somewhere before cliff ends

        {
            (, , , uint256 unclaimedBeforeSplit, uint256 splitCount, , , , , , ) = govNFT.locks(tokenId);
            assertEq(unclaimedBeforeSplit, 0);
            assertEq(splitCount, 0);
        }

        (totalLocked, , , , , cliffLength, start, end, , vault, ) = govNFT.locks(tokenId);
        assertEq(totalLocked, govNFT.locked(tokenId)); // still on cliff, no tokens vested
        assertEq(IERC20(testToken).balanceOf(vault), totalLocked);

        vm.expectEmit(true, true, false, true);
        emit Split(
            tokenId,
            tokenId + 1,
            address(recipient2),
            totalLocked - amount / 2,
            amount / 2,
            block.timestamp,
            end
        );
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(tokenId);
        vm.prank(address(recipient));
        uint256 tokenId2 = govNFT.split(address(recipient2), tokenId, amount / 2, block.timestamp, end, WEEK - 4 days);

        (, , , , , , , , , splitVault, ) = govNFT.locks(tokenId2);

        // original NFT assertions
        remainingCliff = (start + cliffLength) - block.timestamp;
        // since still on cliff and vesting has started, the split cliff length will be
        // the remaining cliff period and the new start will be the current timestamp
        _checkLockUpdates(tokenId, totalLocked - amount / 2, totalLocked, remainingCliff, block.timestamp, end);
        _checkSplitInfo(tokenId, tokenId2, address(recipient), address(recipient2), 0, 1);
        assertEq(remainingCliff, WEEK - 4 days);

        // split NFT assertions
        _checkLockUpdates(tokenId2, amount / 2, amount / 2, remainingCliff, block.timestamp, end);
    }

    function testRecursiveSplitAfterCliffEnd() public {
        skip(WEEK + 2 days); // skip somewhere after cliff ends

        (uint256 totalLocked, , , , , uint256 cliffLength, uint256 start, uint256 end, , address vault, ) = govNFT
            .locks(from);
        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);
        assertEq(IERC20(testToken).balanceOf(vault), totalLocked);
        {
            (, , , uint256 unclaimedBeforeSplit, uint256 splitCount, , , , , , ) = govNFT.locks(from);
            assertEq(unclaimedBeforeSplit, 0);
            assertEq(splitCount, 0);
        }

        vm.expectEmit(true, true, false, true);
        emit Split(from, from + 2, address(recipient), lockedBeforeSplit - amount, amount, block.timestamp, end);
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        vm.prank(address(recipient));
        uint256 tokenId = govNFT.split(address(recipient), from, amount, block.timestamp, end, 0);

        (, , , , , , , , , address splitVault, ) = govNFT.locks(tokenId);

        assertEq(totalLocked, govNFT.locked(from) + govNFT.locked(tokenId) + originalUnclaimed);

        // original NFT assertions
        (uint256 totalLockedSplit, , , , , , , , , , ) = govNFT.locks(from);

        // no cliff since vesting has already started
        _checkLockUpdates(from, lockedBeforeSplit - amount, totalLocked, 0, block.timestamp, end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient), originalUnclaimed, 1);
        assertEq(govNFT.locked(from), totalLockedSplit);

        // split NFT assertions
        (totalLockedSplit, , , , , , , , , , ) = govNFT.locks(tokenId);

        // no cliff since vesting has already started
        _checkLockUpdates(tokenId, amount, amount, 0, block.timestamp, end);
        assertEq(govNFT.locked(tokenId), totalLockedSplit);

        // second split checks
        skip(2 days);

        {
            (, , , uint256 unclaimedBeforeSplit, uint256 splitCount, , , , , , ) = govNFT.locks(tokenId);
            assertEq(unclaimedBeforeSplit, 0);
            assertEq(splitCount, 0);
        }

        (totalLocked, , , , , cliffLength, start, end, , vault, ) = govNFT.locks(tokenId);

        lockedBeforeSplit = govNFT.locked(tokenId);
        originalUnclaimed = govNFT.unclaimed(tokenId);
        assertEq(IERC20(testToken).balanceOf(vault), totalLocked);

        vm.expectEmit(true, true, false, true);
        emit Split(
            tokenId,
            tokenId + 1,
            address(recipient2),
            lockedBeforeSplit - amount / 2,
            amount / 2,
            block.timestamp,
            end
        );
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(tokenId);
        vm.prank(address(recipient));
        uint256 tokenId2 = govNFT.split(address(recipient2), tokenId, amount / 2, block.timestamp, end, 0);

        (, , , , , , , , , splitVault, ) = govNFT.locks(tokenId2);

        assertEq(totalLocked, govNFT.locked(tokenId) + govNFT.locked(tokenId2) + originalUnclaimed);

        // original NFT assertions
        (totalLockedSplit, , , , , , , , , , ) = govNFT.locks(tokenId);

        // no cliff since vesting has already started
        _checkLockUpdates(tokenId, lockedBeforeSplit - amount / 2, totalLocked, 0, block.timestamp, end);
        _checkSplitInfo(tokenId, tokenId2, address(recipient), address(recipient2), originalUnclaimed, 1);
        assertEq(govNFT.locked(tokenId), totalLockedSplit);

        // split NFT assertions
        (totalLockedSplit, , , , , , , , , , ) = govNFT.locks(tokenId2);

        // no cliff since vesting has already started
        _checkLockUpdates(tokenId2, amount / 2, amount / 2, 0, block.timestamp, end);
        assertEq(govNFT.locked(tokenId2), totalLockedSplit);
    }

    function testSplitPermissions() public {
        (uint256 totalLocked, , , , , , uint256 start, uint256 end, , , address minter) = govNFT.locks(from);
        assertEq(minter, address(admin));

        address approvedUser = makeAddr("alice");
        assertEq(govNFT.balanceOf(approvedUser), 0);

        vm.prank(address(recipient));
        govNFT.approve(approvedUser, from);

        // can split after getting approval on nft
        vm.prank(approvedUser);
        vm.expectEmit(true, true, false, true);
        emit Split(from, from + 2, approvedUser, totalLocked - TOKEN_1, TOKEN_1, start, end);
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        uint256 tokenId = govNFT.split(approvedUser, from, TOKEN_1, block.timestamp, block.timestamp + 3 * WEEK, WEEK);

        (, , , , , , , , , , address splitMinter) = govNFT.locks(tokenId);

        assertEq(govNFT.ownerOf(tokenId), approvedUser);
        assertEq(govNFT.balanceOf(approvedUser), 1);
        // split updates minter in child lock
        assertEq(splitMinter, approvedUser);

        address approvedForAllUser = makeAddr("bob");
        assertEq(govNFT.balanceOf(approvedForAllUser), 0);

        vm.prank(address(recipient));
        govNFT.setApprovalForAll(approvedForAllUser, true);

        // can split after getting approval for all nfts
        vm.prank(approvedForAllUser);
        vm.expectEmit(true, true, false, true);
        emit Split(from, tokenId + 1, approvedForAllUser, totalLocked - TOKEN_1 * 2, TOKEN_1, start, end);
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        tokenId = govNFT.split(approvedForAllUser, from, TOKEN_1, block.timestamp, block.timestamp + 3 * WEEK, WEEK);

        (, , , , , , , , , , splitMinter) = govNFT.locks(tokenId);

        assertEq(govNFT.ownerOf(tokenId), approvedForAllUser);
        assertEq(govNFT.balanceOf(approvedForAllUser), 1);
        // split updates minter in child lock
        assertEq(splitMinter, approvedForAllUser);
    }

    function testCannotSplitIfNotRecipientOrApproved() public {
        address testUser = makeAddr("alice");

        vm.prank(testUser);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, testUser, from));
        govNFT.split(address(recipient2), from, TOKEN_1, block.timestamp, block.timestamp + 3 * WEEK, WEEK);

        vm.prank(address(admin));
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(admin), from)
        );
        govNFT.split(address(recipient2), from, TOKEN_1, block.timestamp, block.timestamp + 3 * WEEK, WEEK);
    }

    function testCannotSplitNonExistentToken() public {
        uint256 tokenId = from + 2;
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient), TOKEN_100K);
    }

    function testCannotSplitIfZeroAmount() public {
        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.ZeroAmount.selector);
        govNFT.split(address(recipient2), from, 0, block.timestamp, block.timestamp + 3 * WEEK, WEEK);
    }

    function testCannotSplitIfAmountTooBig() public {
        skip(WEEK + 1);

        uint256 lockedBalance = govNFT.locked(from);
        (, , , , , uint256 cliffLength, , uint256 end, , , ) = govNFT.locks(from);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.AmountTooBig.selector);
        govNFT.split(address(recipient2), from, lockedBalance + 1, block.timestamp, end, 0);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.AmountTooBig.selector);
        govNFT.split(address(recipient2), from, lockedBalance, block.timestamp, end, cliffLength);

        skip(WEEK + 1 days);

        lockedBalance = govNFT.locked(from);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.AmountTooBig.selector);
        govNFT.split(address(recipient2), from, lockedBalance + 1, block.timestamp, block.timestamp + WEEK * 3, WEEK);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.AmountTooBig.selector);
        govNFT.split(address(recipient2), from, lockedBalance, block.timestamp, block.timestamp + WEEK * 3, WEEK);
    }

    function testCannotSplitIfVestingIsFinished() public {
        skip(WEEK * 3);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.AmountTooBig.selector);
        govNFT.split(address(recipient2), from, amount, block.timestamp, block.timestamp + WEEK * 3, WEEK);
    }

    function testSplitTokensByIndex(uint8 splits) public {
        vm.startPrank(address(recipient));
        uint256[] memory tokens = new uint256[](splits);
        uint256 tokenId;
        uint256 splitCount;
        // create multiple splits
        for (uint256 i = 0; i < splits; i++) {
            assertEq(govNFT.balanceOf(address(recipient2)), i);
            (, , , , splitCount, , , , , , ) = govNFT.locks(from);
            assertEq(splitCount, i);

            tokenId = govNFT.split(
                address(recipient2),
                from,
                TOKEN_1,
                block.timestamp,
                block.timestamp + WEEK * 3,
                WEEK
            );
            tokens[i] = tokenId;

            assertEq(govNFT.balanceOf(address(recipient2)), i + 1);
            (, , , , splitCount, , , , , , ) = govNFT.locks(from);
            assertEq(splitCount, i + 1);
        }
        // assert all splits are in list
        (, , , , splitCount, , , , , , ) = govNFT.locks(from);
        for (uint256 i = 0; i < splitCount; i++) {
            assertEq(govNFT.splitTokensByIndex(from, i), tokens[i]);
        }
    }

    function testSplitToUpdatesTimestamps() public {
        (uint256 totalLocked, , , , , uint256 cliffLength, uint256 start, uint256 end, , , ) = govNFT.locks(from1);

        vm.prank(address(recipient));
        vm.expectEmit(true, true, false, true);
        emit Split(from1, from1 + 1, address(recipient2), totalLocked - amount, amount, start + WEEK, end + WEEK);
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from1);
        uint256 tokenId = govNFT.split(
            address(recipient2),
            from1,
            amount,
            start + WEEK,
            end + WEEK,
            cliffLength + WEEK
        );

        // token 1 assertions
        (
            uint256 totalLockedSplit,
            ,
            ,
            ,
            ,
            uint256 cliffLengthSplit,
            uint256 startSplit,
            uint256 endSplit,
            ,
            ,

        ) = govNFT.locks(from1);

        assertEq(endSplit, end);
        assertEq(startSplit, start);
        assertEq(cliffLengthSplit, cliffLength);
        assertEq(govNFT.ownerOf(from1), address(recipient));

        // token 2 assertions
        (totalLockedSplit, , , , , cliffLengthSplit, startSplit, endSplit, , , ) = govNFT.locks(tokenId);

        assertEq(endSplit, end + WEEK);
        assertEq(startSplit, start + WEEK);
        assertEq(cliffLengthSplit, cliffLength + WEEK);
        assertEq(govNFT.ownerOf(tokenId), address(recipient2));

        skip(end); // skips to end of tokenId1 vesting
        // vesting is finished for token1
        assertEq(govNFT.unclaimed(from1), totalLocked - amount);
        assertEq(govNFT.locked(from1), 0);

        vm.prank(address(recipient));
        govNFT.claim(from1, address(recipient), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), totalLocked - amount);

        // vesting is not finished for token2
        assertLt(govNFT.unclaimed(tokenId), amount);
        assertGt(govNFT.locked(tokenId), 0);

        skip(endSplit); // skips to end of tokenId vesting
        // vesting is finished for token2
        assertEq(govNFT.unclaimed(tokenId), amount);
        assertEq(govNFT.locked(tokenId), 0);

        vm.prank(address(recipient2));
        govNFT.claim(tokenId, address(recipient2), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), amount);
    }

    function testSplitToIncreaseStart(uint32 _delta) public {
        uint256 delta = uint256(_delta);
        (uint256 totalLocked, , , , , uint256 cliffLength, uint256 start, uint256 end, , , ) = govNFT.locks(from1);
        vm.assume(delta < end - start - cliffLength); // avoid invalidcliff

        vm.prank(address(recipient));
        vm.expectEmit(true, true, false, true);
        emit Split(from1, from1 + 1, address(recipient2), totalLocked - amount, amount, start + delta, end);
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from1);
        uint256 tokenId = govNFT.split(address(recipient2), from1, amount, start + delta, end, cliffLength);

        // token 1 assertions
        (
            uint256 totalLockedSplit,
            ,
            ,
            ,
            ,
            uint256 cliffLengthSplit,
            uint256 startSplit,
            uint256 endSplit,
            ,
            ,

        ) = govNFT.locks(from1);

        assertEq(endSplit, end);
        assertEq(startSplit, start);
        assertEq(cliffLengthSplit, cliffLength);
        assertEq(govNFT.ownerOf(from1), address(recipient));

        // token 2 assertions
        (totalLockedSplit, , , , , cliffLengthSplit, startSplit, endSplit, , , ) = govNFT.locks(tokenId);

        assertEq(endSplit, end);
        assertEq(startSplit, start + delta);
        assertEq(cliffLengthSplit, cliffLength);
        assertEq(govNFT.ownerOf(tokenId), address(recipient2));
    }

    function testSplitToIncreaseEnd(uint32 _delta) public {
        uint256 delta = uint256(_delta);
        (uint256 totalLocked, , , , , uint256 cliffLength, uint256 start, uint256 end, , , ) = govNFT.locks(from1);

        vm.prank(address(recipient));
        vm.expectEmit(true, true, false, true);
        emit Split(from1, from1 + 1, address(recipient2), totalLocked - amount, amount, start, end + delta);
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from1);
        uint256 tokenId = govNFT.split(address(recipient2), from1, amount, start, end + delta, cliffLength);

        // token 1 assertions
        (
            uint256 totalLockedSplit,
            ,
            ,
            ,
            ,
            uint256 cliffLengthSplit,
            uint256 startSplit,
            uint256 endSplit,
            ,
            ,

        ) = govNFT.locks(from1);

        assertEq(endSplit, end);
        assertEq(startSplit, start);
        assertEq(cliffLengthSplit, cliffLength);
        assertEq(govNFT.ownerOf(from1), address(recipient));

        // token 2 assertions
        (totalLockedSplit, , , , , cliffLengthSplit, startSplit, endSplit, , , ) = govNFT.locks(tokenId);

        assertEq(startSplit, start);
        assertEq(endSplit, end + delta);
        assertEq(cliffLengthSplit, cliffLength);
        assertEq(govNFT.ownerOf(tokenId), address(recipient2));
    }

    function testSplitToIncreaseCliff(uint32 _cliff) public {
        uint256 delta = uint256(_cliff);
        (uint256 totalLocked, , , , , uint256 cliffLength, uint256 start, uint256 end, , , ) = govNFT.locks(from1);
        delta = bound(delta, 0, end - start - cliffLength);

        vm.prank(address(recipient));
        vm.expectEmit(true, true, false, true);
        emit Split(from1, from1 + 1, address(recipient2), totalLocked - amount, amount, start, end);
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from1);
        uint256 tokenId = govNFT.split(address(recipient2), from1, amount, start, end, cliffLength + delta);

        // token 1 assertions
        (
            uint256 totalLockedSplit,
            ,
            ,
            ,
            ,
            uint256 cliffLengthSplit,
            uint256 startSplit,
            uint256 endSplit,
            ,
            ,

        ) = govNFT.locks(from1);

        assertEq(endSplit, end);
        assertEq(startSplit, start);
        assertEq(cliffLengthSplit, cliffLength);
        assertEq(govNFT.ownerOf(from1), address(recipient));

        // token 2 assertions
        (totalLockedSplit, , , , , cliffLengthSplit, startSplit, endSplit, , , ) = govNFT.locks(tokenId);

        assertEq(startSplit, start);
        assertEq(endSplit, end);
        assertEq(cliffLengthSplit, cliffLength + delta);
        assertEq(govNFT.ownerOf(tokenId), address(recipient2));
    }

    function testSplitToIncreaseStartDecreaseCliff(uint32 _start, uint32 _cliff) public {
        uint256 startDelta = uint256(_start);
        (uint256 totalLocked, , , , , uint256 cliffLength, uint256 start, uint256 end, , , ) = govNFT.locks(from1);
        vm.assume(startDelta < end - start - cliffLength); // avoid invalidcliff
        uint256 cliffDelta = uint256(_cliff);
        vm.assume(cliffDelta <= startDelta);

        vm.prank(address(recipient));
        vm.expectEmit(true, true, false, true);
        emit Split(from1, from1 + 1, address(recipient2), totalLocked - amount, amount, start + startDelta, end);
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from1);
        uint256 tokenId = govNFT.split(
            address(recipient2),
            from1,
            amount,
            start + startDelta,
            end,
            cliffLength - cliffDelta
        );

        // token 1 assertions
        (
            uint256 totalLockedSplit,
            ,
            ,
            ,
            ,
            uint256 cliffLengthSplit,
            uint256 startSplit,
            uint256 endSplit,
            ,
            ,

        ) = govNFT.locks(from1);

        assertEq(endSplit, end);
        assertEq(startSplit, start);
        assertEq(cliffLengthSplit, cliffLength);
        assertEq(govNFT.ownerOf(from1), address(recipient));

        // token 2 assertions
        (totalLockedSplit, , , , , cliffLengthSplit, startSplit, endSplit, , , ) = govNFT.locks(tokenId);

        assertEq(startSplit, start + startDelta);
        assertEq(endSplit, end);
        assertEq(cliffLengthSplit, cliffLength - cliffDelta);
        assertEq(govNFT.ownerOf(tokenId), address(recipient2));
    }

    function testCannotSplitToIfInvalidStart() public {
        (, , , , , uint256 cliff, uint256 start, uint256 end, , , ) = govNFT.locks(from1);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.InvalidStart.selector);
        // new vesting cannot start before original vesting starts
        govNFT.split(address(recipient2), from1, amount, start - 1, end, cliff);

        skip(WEEK + 1 days); //skip to after vesting start

        // start cannot be before block.timestamp, even if after original vesting starts
        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.InvalidStart.selector);
        govNFT.split(address(recipient2), from1, amount, start + 1, end, cliff);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.InvalidStart.selector);
        govNFT.split(address(recipient2), from1, amount, block.timestamp - 1, end, cliff);
    }

    function testCannotSplitToIfInvalidEnd() public {
        (, , , , , uint256 cliff, uint256 start, uint256 end, , , ) = govNFT.locks(from1);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.InvalidEnd.selector);
        govNFT.split(address(recipient2), from1, amount, start, end - 1, cliff);
    }

    function testCannotSplitToIfEndBeforeOrEqualStart() public {
        (, , , , , , , uint256 end, , , ) = govNFT.locks(from1);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.EndBeforeOrEqualStart.selector);
        govNFT.split(address(recipient2), from1, amount, end + 1, end, 0);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.EndBeforeOrEqualStart.selector);
        govNFT.split(address(recipient2), from1, amount, end, end, 0);
    }

    function testCannotSplitToIfInvalidCliff() public {
        (, , , , , uint256 cliff, uint256 start, uint256 end, , , ) = govNFT.locks(from1);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.InvalidCliff.selector);
        govNFT.split(address(recipient2), from1, amount, start, end, cliff - 1);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.InvalidCliff.selector);
        govNFT.split(address(recipient2), from1, amount, end - cliff / 2, end, cliff);
    }

    function testCannotSplitToZeroAddress() public {
        (, , , , , uint256 cliff, uint256 start, uint256 end, , , ) = govNFT.locks(from1);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFT.ZeroAddress.selector);
        govNFT.split(address(0), from1, amount, start, end, cliff);
    }
}
