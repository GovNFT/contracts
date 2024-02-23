// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import {IERC721Errors} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";

import "test/utils/BaseTest.sol";

contract FinalizeSplitTest is BaseTest {
    uint256 public from;
    uint256 public amount;
    uint256 public timelockDelay = 1 days;
    GovNFTTimelock public govNFTLock;

    function _setUp() public override {
        govNFTLock = new GovNFTTimelock(address(admin), address(0), "GovNFTTimelock", SYMBOL, timelockDelay);
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

    function test_FinalizeSplitBeforeStart() public {
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

        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: start,
            end: end,
            cliff: cliffLength
        });
        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit(from, address(recipient2), amount, start, end);
        vm.startPrank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 1);
        assertEq(govNFTLock.proposedSplits(from).timestamp, block.timestamp);

        skip(timelockDelay);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split(
            from,
            from + 1,
            address(recipient2),
            totalLocked - amount,
            amount,
            start + timelockDelay,
            end
        );
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
            totalLocked - amount,
            totalLocked,
            cliffLength - timelockDelay,
            start + timelockDelay,
            end
        );
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), 0, 1);

        // split NFT assertions
        // start timestamps and cliffs remain the same as parent token
        _checkLockUpdates(tokenId, amount, amount, cliffLength - timelockDelay, start + timelockDelay, end);
    }

    function test_FinalizeSplitClaimsBeforeStart() public {
        (uint256 totalLocked, , uint256 totalClaimed, , , , uint256 start, uint256 end, , , ) = govNFT.locks(from);
        assertEq(totalClaimed, 0);

        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: start,
            end: end,
            cliff: WEEK
        });
        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit(from, address(recipient2), amount, start, end);
        vm.startPrank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        skip(timelockDelay);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split(
            from,
            from + 1,
            address(recipient2),
            totalLocked - amount,
            amount,
            start + timelockDelay,
            end
        );
        vm.expectEmit(false, false, false, true, address(govNFTLock));
        emit IERC4906.MetadataUpdate(from);
        uint256 tokenId = govNFTLock.finalizeSplit(from)[0];
        vm.stopPrank();

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

    function test_FinalizeSplitBeforeCliffEnd() public {
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

        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: block.timestamp,
            end: end,
            cliff: WEEK - 5 days
        });

        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit(from, address(recipient2), amount, block.timestamp, end);
        vm.startPrank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 1);
        assertEq(govNFTLock.proposedSplits(from).timestamp, block.timestamp);

        skip(timelockDelay);

        emit IGovNFT.Split(from, from + 1, address(recipient2), totalLocked - amount, amount, block.timestamp, end);
        vm.expectEmit(false, false, false, true, address(govNFTLock));
        emit IERC4906.MetadataUpdate(from);
        uint256 tokenId = govNFTLock.finalizeSplit(from)[0];
        vm.stopPrank();

        assertEq(govNFTLock.proposedSplits(from).timestamp, 0);
        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 0);

        // original NFT assertions
        uint256 remainingCliff = (start + cliffLength) - block.timestamp;
        // since still on cliff and vesting has started, the split cliff length will be
        // the remaining cliff period and the new start will be the current timestamp
        _checkLockUpdates(from, totalLocked - amount, totalLocked, remainingCliff, block.timestamp, end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), 0, 1);
        assertEq(remainingCliff, WEEK - (5 days + timelockDelay));

        // split NFT assertions
        _checkLockUpdates(tokenId, amount, amount, remainingCliff, block.timestamp, end);
    }

    function test_FinalizeSplitClaimsBeforeCliffEnd() public {
        skip(5 days); // skip somewhere before cliff ends

        (uint256 totalLocked, , uint256 totalClaimed, , , , , uint256 end, , , ) = govNFT.locks(from);
        assertEq(totalClaimed, 0);

        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: block.timestamp,
            end: end,
            cliff: WEEK - 5 days
        });

        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit(from, address(recipient2), amount, block.timestamp, end);
        vm.startPrank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        skip(timelockDelay);

        emit IGovNFT.Split(from, from + 1, address(recipient2), totalLocked - amount, amount, block.timestamp, end);
        vm.expectEmit(false, false, false, true, address(govNFTLock));
        emit IERC4906.MetadataUpdate(from);
        uint256 tokenId = govNFTLock.finalizeSplit(from)[0];
        vm.stopPrank();

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

    function test_FinalizeSplitAfterCliffEnd() public {
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
        assertEq(IERC20(testToken).balanceOf(vault), totalLocked);

        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: block.timestamp,
            end: end,
            cliff: 0
        });
        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit(from, address(recipient2), amount, block.timestamp, end);
        vm.startPrank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 1);
        assertEq(govNFTLock.proposedSplits(from).timestamp, block.timestamp);

        skip(timelockDelay);

        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split(
            from,
            from + 1,
            address(recipient2),
            lockedBeforeSplit - amount,
            amount,
            block.timestamp,
            end
        );
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        uint256 tokenId = govNFTLock.finalizeSplit(from)[0];
        vm.stopPrank();

        assertEq(govNFTLock.proposedSplits(from).timestamp, 0);
        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 0);

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

    function test_FinalizeSplitAfterCliffEndAndClaim() public {
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
        assertEq(IERC20(testToken).balanceOf(vault), totalLocked - totalClaimed);

        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: block.timestamp,
            end: end,
            cliff: 0
        });
        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit(from, address(recipient2), amount, block.timestamp, end);
        vm.startPrank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 1);
        assertEq(govNFTLock.proposedSplits(from).timestamp, block.timestamp);

        skip(timelockDelay);

        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split(
            from,
            from + 1,
            address(recipient2),
            lockedBeforeSplit - amount,
            amount,
            block.timestamp,
            end
        );
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        uint256 tokenId = govNFTLock.finalizeSplit(from)[0];
        vm.stopPrank();

        assertEq(govNFTLock.proposedSplits(from).timestamp, 0);
        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 0);

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

    function testFuzz_FinalizeSplitAfterCliffEnd(uint32 delay) public {
        (
            uint256 totalLocked,
            ,
            ,
            uint256 unclaimedBeforeSplit,
            uint256 splitCount,
            uint256 cliff,
            uint256 start,
            uint256 end,
            ,
            address vault,

        ) = govNFT.locks(from);
        delay = uint32(bound(delay, 0, end - (start + cliff) - 2 days));

        skip(cliff); // skip cliff, so that tokens start vesting right away
        assertEq(unclaimedBeforeSplit, 0);
        assertEq(splitCount, 0);
        assertEq(IERC20(testToken).balanceOf(vault), totalLocked);

        // using a small split amount to avoid amounttoobig revert
        uint256 splitAmount = 10 * TOKEN_1;
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: splitAmount,
            start: block.timestamp,
            end: end,
            cliff: 0
        });
        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit(from, address(recipient2), splitAmount, block.timestamp, end);
        vm.startPrank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 1);
        assertEq(govNFTLock.proposedSplits(from).timestamp, block.timestamp);

        skip(timelockDelay + delay);

        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split(
            from,
            from + 1,
            address(recipient2),
            lockedBeforeSplit - splitAmount,
            splitAmount,
            block.timestamp,
            end
        );
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        uint256 tokenId = govNFTLock.finalizeSplit(from)[0];
        vm.stopPrank();

        assertEq(govNFTLock.proposedSplits(from).timestamp, 0);
        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 0);

        assertEq(totalLocked, govNFT.locked(from) + govNFT.locked(tokenId) + originalUnclaimed);

        // original NFT assertions
        (uint256 totalLockedSplit, , , , , , , , , , ) = govNFT.locks(from);

        // no cliff since vesting has already started
        _checkLockUpdates(from, lockedBeforeSplit - splitAmount, totalLocked, 0, block.timestamp, end);
        _checkSplitInfo(from, tokenId, address(recipient), address(recipient2), originalUnclaimed, 1);
        assertEq(govNFT.locked(from), totalLockedSplit);

        // split NFT assertions
        (totalLockedSplit, , , , , , , , , , ) = govNFT.locks(tokenId);

        // no cliff since vesting has already started
        _checkLockUpdates(tokenId, splitAmount, splitAmount, 0, block.timestamp, end);

        assertEq(govNFT.locked(tokenId), totalLockedSplit);
    }

    function test_FinalizeSplitClaimsWithUnclaimedRewardsAfterCliffEnd() public {
        skip(WEEK + 2 days); // skip somewhere after cliff ends

        (uint256 totalLocked, , uint256 totalClaimed, uint256 unclaimedBeforeSplit, , , , uint256 end, , , ) = govNFT
            .locks(from);
        assertEq(unclaimedBeforeSplit, 0);
        assertEq(totalClaimed, 0);

        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: block.timestamp,
            end: end,
            cliff: 0
        });
        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit(from, address(recipient2), amount, block.timestamp, end);
        vm.startPrank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        skip(timelockDelay);

        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split(
            from,
            from + 1,
            address(recipient2),
            lockedBeforeSplit - amount,
            amount,
            block.timestamp,
            end
        );
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        uint256 tokenId = govNFTLock.finalizeSplit(from)[0];
        vm.stopPrank();

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

    function testFuzz_FinalizeSplitClaimsWithUnclaimedRewardsAfterCliffEnd(uint32 delay) public {
        (uint256 totalLocked, , , , , uint256 cliff, uint256 start, uint256 end, , , ) = govNFT.locks(from);
        delay = uint32(bound(delay, 0, end - (start + cliff) - 2 days));

        skip(cliff); // skip cliff, so that tokens start vesting right away

        {
            (, , uint256 totalClaimed, uint256 unclaimedBeforeSplit, , , , , , , ) = govNFT.locks(from);
            assertEq(unclaimedBeforeSplit, 0);
            assertEq(totalClaimed, 0);
        }

        // using a small split amount to avoid amounttoobig revert
        uint256 splitAmount = 10 * TOKEN_1;
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: splitAmount,
            start: block.timestamp,
            end: end,
            cliff: 0
        });
        vm.expectEmit(true, true, false, true);
        emit IGovNFTTimelock.CommitSplit(from, address(recipient2), splitAmount, block.timestamp, end);
        vm.startPrank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        skip(timelockDelay + delay);

        uint256 lockedBeforeSplit = govNFT.locked(from);
        uint256 originalUnclaimed = govNFT.unclaimed(from);

        vm.expectEmit(true, true, false, true);
        emit IGovNFT.Split(
            from,
            from + 1,
            address(recipient2),
            lockedBeforeSplit - splitAmount,
            splitAmount,
            block.timestamp,
            end
        );
        vm.expectEmit(false, false, false, true, address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        uint256 tokenId = govNFTLock.finalizeSplit(from)[0];
        vm.stopPrank();

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

        _checkLockedUnclaimedSplit(from, lockedBeforeSplit - splitAmount, originalUnclaimed, tokenId, splitAmount, 0);

        skip(endSplit - block.timestamp);

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
        govNFT.claim(from, address(recipient), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), originalUnclaimed + lockedBeforeSplit - splitAmount);

        {
            (, , uint256 totalClaimed, , , , , , , , ) = govNFT.locks(from);
            assertEq(totalClaimed, lockedBeforeSplit - splitAmount); //unclaimed before split not included
        }

        vm.prank(address(recipient2));
        govNFT.claim(tokenId, address(recipient2), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), splitAmount);
        {
            (, , uint256 totalClaimed, , , , , , , , ) = govNFT.locks(tokenId);
            assertEq(totalClaimed, splitAmount);
        }
    }

    function test_RevertIf_FinalizeSplitAmountTooBig() public {
        (, , , , , uint256 cliffLength, uint256 start, uint256 end, , , ) = govNFT.locks(from);

        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);

        // skip some time to vest tokens
        skip((end - start) / 2);

        // the max amount that can be split in this timestamp is `lockedAmount`
        uint256 lockedAmount = govNFTLock.locked(from);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: lockedAmount,
            start: block.timestamp,
            end: end,
            cliff: cliffLength
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
        (, , , , , uint256 cliffLength, uint256 start, uint256 end, , , ) = govNFT.locks(from);

        // skip some time to vest tokens
        skip((end - start) / 2);

        uint256 lockedAmount = govNFTLock.locked(from);

        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](2);
        // sum of amounts should not be greater than locked value at the time of finalization
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: lockedAmount / 2,
            start: block.timestamp,
            end: end,
            cliff: cliffLength
        });
        paramsList[1] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: lockedAmount / 2,
            start: block.timestamp,
            end: end,
            cliff: cliffLength
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
        (, , , , , uint256 cliffLength, uint256 start, uint256 end, , , ) = govNFT.locks(from);

        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: start,
            end: end,
            cliff: cliffLength
        });
        vm.startPrank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 1);
        assertEq(govNFTLock.proposedSplits(from).timestamp, block.timestamp);

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

        vm.warp(end - timelockDelay); // when timelockDelay is passed, parentLock will have stopped vesting

        assertEq(unclaimedBeforeSplit, 0);
        assertEq(splitCount, 0);
        assertEq(IERC20(testToken).balanceOf(vault), totalLocked);

        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: TOKEN_1 * 1000,
            start: block.timestamp,
            end: end + WEEK,
            cliff: 0
        });
        vm.startPrank(address(recipient));
        govNFTLock.commitSplit(from, paramsList);

        assertEq(govNFTLock.proposedSplits(from).pendingSplits.length, 1);
        assertEq(govNFTLock.proposedSplits(from).timestamp, block.timestamp);

        // this skip reaches `parentLock.end`, vesting all of the parenLock's tokens
        skip(timelockDelay);

        // `from` has 0 tokens locked, cannot perform any split
        vm.expectRevert(IGovNFT.AmountTooBig.selector);
        govNFTLock.finalizeSplit(from);
    }
}
