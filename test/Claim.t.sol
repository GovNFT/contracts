// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract ClaimTest is BaseTest {
    function test_ClaimFull() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            uint40(block.timestamp),
            uint40(block.timestamp) + WEEK * 2,
            WEEK
        );

        IGovNFT.Lock memory lock = govNFT.locks(tokenId);

        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);
        assertEq(govNFT.locked(tokenId), lock.totalLocked);
        assertEq(lock.totalClaimed, 0);
        assertEq(govNFT.unclaimed(tokenId), 0);

        skip(WEEK * 2); //skip to the vesting end timestamp

        lock = govNFT.locks(tokenId);
        assertEq(govNFT.unclaimed(tokenId), lock.totalLocked);
        assertEq(lock.totalClaimed, 0);
        assertEq(govNFT.locked(tokenId), 0);

        vm.expectEmit(true, true, false, true, address(govNFT));
        emit IGovNFT.Claim({tokenId: tokenId, recipient: address(recipient), claimed: lock.totalLocked});
        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient), lock.totalLocked);

        lock = govNFT.locks(tokenId);
        assertEq(govNFT.locked(tokenId), 0);
        assertEq(govNFT.unclaimed(tokenId), 0);
        assertEq(lock.totalClaimed, lock.totalLocked);
        assertEq(IERC20(testToken).balanceOf(lock.vault), 0);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), lock.totalLocked);
    }

    function test_ClaimBeneficiary() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            uint40(block.timestamp),
            uint40(block.timestamp) + WEEK * 2,
            WEEK
        );
        address beneficiary = makeAddr("alice");

        IGovNFT.Lock memory lock = govNFT.locks(tokenId);

        skip(WEEK * 2);
        vm.prank(address(recipient));
        vm.expectEmit(true, true, false, true, address(govNFT));
        emit IGovNFT.Claim({tokenId: tokenId, recipient: beneficiary, claimed: lock.totalLocked});
        govNFT.claim(tokenId, beneficiary, lock.totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(beneficiary), lock.totalLocked);
    }

    function test_ClaimLess() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            uint40(block.timestamp),
            uint40(block.timestamp) + WEEK * 2,
            WEEK
        );

        IGovNFT.Lock memory lock = govNFT.locks(tokenId);

        skip(WEEK * 2);
        assertEq(govNFT.unclaimed(tokenId), lock.totalLocked);
        address beneficiary = makeAddr("alice");
        address beneficiary2 = makeAddr("bob");

        vm.prank(address(recipient));
        vm.expectEmit(true, true, false, true, address(govNFT));
        emit IGovNFT.Claim({tokenId: tokenId, recipient: beneficiary, claimed: lock.totalLocked / 10});
        govNFT.claim(tokenId, beneficiary, lock.totalLocked / 10);

        lock = govNFT.locks(tokenId);
        assertEq(govNFT.unclaimed(tokenId), (9 * lock.totalLocked) / 10);
        assertEq(lock.totalClaimed, lock.totalLocked / 10);
        assertEq(IERC20(testToken).balanceOf(beneficiary), lock.totalLocked / 10);
        assertEq(IERC20(testToken).balanceOf(lock.vault), (lock.totalLocked * 9) / 10);

        vm.prank(address(recipient));
        vm.expectEmit(true, true, false, true, address(govNFT));
        emit IGovNFT.Claim({tokenId: tokenId, recipient: beneficiary2, claimed: lock.totalLocked / 10});
        govNFT.claim(tokenId, beneficiary2, lock.totalLocked / 10);

        lock = govNFT.locks(tokenId);
        assertEq(govNFT.unclaimed(tokenId), (8 * lock.totalLocked) / 10);
        assertEq(lock.totalClaimed, (2 * lock.totalLocked) / 10);
        assertEq(IERC20(testToken).balanceOf(beneficiary2), lock.totalLocked / 10);
        assertEq(IERC20(testToken).balanceOf(lock.vault), (lock.totalLocked * 8) / 10);

        vm.prank(address(recipient));
        vm.expectEmit(true, true, false, true, address(govNFT));
        emit IGovNFT.Claim({tokenId: tokenId, recipient: address(recipient), claimed: (lock.totalLocked / 10) * 8});
        govNFT.claim(tokenId, address(recipient), lock.totalLocked); // claims remaining tokens

        lock = govNFT.locks(tokenId);
        assertEq(govNFT.unclaimed(tokenId), 0);
        assertEq(lock.totalClaimed, lock.totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(lock.vault), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), (8 * lock.totalLocked) / 10);
    }

    function testFuzz_ClaimPartial(uint40 timeskip) public {
        uint40 _start = uint40(block.timestamp);
        uint40 _end = _start + WEEK * 6;
        timeskip = uint40(bound(timeskip, 0, _end - _start));
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock(testToken, address(recipient), TOKEN_100K, _start, _end, 0);

        IGovNFT.Lock memory lock = govNFT.locks(tokenId);

        skip(timeskip);

        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient), lock.totalLocked); // claims available tokens
        uint256 expectedAmount = Math.min(
            (lock.totalLocked * (uint40(block.timestamp) - lock.start)) / (lock.end - lock.start),
            lock.totalLocked
        );

        lock = govNFT.locks(tokenId);
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked - expectedAmount);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), expectedAmount);
        assertEq(lock.totalClaimed, expectedAmount);
        assertEq(govNFT.unclaimed(tokenId), 0);
    }

    function testFuzz_MultipleClaims(uint8 _cycles) public {
        vm.assume(_cycles > 0);
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            uint40(block.timestamp),
            uint40(block.timestamp) + WEEK * 2,
            0
        );
        IGovNFT.Lock memory lock = govNFT.locks(tokenId);
        IERC20 token = IERC20(testToken);

        uint256 duration = lock.end - lock.start;
        uint256 cycles = uint256(_cycles);

        uint256 govBalance = token.balanceOf(lock.vault);
        uint256 balance = 0;

        uint256 timeskip = duration / cycles;
        vm.startPrank(address(recipient));
        for (uint256 i = 0; i < cycles; i++) {
            if (i == 0) {
                skip(timeskip + (duration % cycles));
            }
            // remove any dust on first iteration
            else {
                skip(timeskip);
            }

            lock = govNFT.locks(tokenId);
            govNFT.claim(tokenId, address(recipient), lock.totalLocked); // claims available tokens
            uint256 expectedAmount = ((lock.totalLocked * (uint40(block.timestamp) - lock.start)) /
                (lock.end - lock.start)) - lock.totalClaimed;

            // assert balance transferred from govnft
            uint256 newBalance = token.balanceOf(lock.vault);
            assertEq(newBalance, govBalance - expectedAmount);
            govBalance = newBalance;

            // assert balance received from recipient
            newBalance = token.balanceOf(address(recipient));
            assertEq(newBalance, balance + expectedAmount);
            balance = newBalance;
        }
        vm.stopPrank();
        assertEq(token.balanceOf(address(recipient)), lock.totalLocked);
        assertEq(token.balanceOf(lock.vault), 0);
        assertEq(token.balanceOf(address(govNFT)), 0);
    }

    function test_NoClaimedRewardsBeforeStart() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            uint40(block.timestamp) + WEEK,
            uint40(block.timestamp) + WEEK * 3,
            WEEK
        );
        IGovNFT.Lock memory lock = govNFT.locks(tokenId);

        skip(WEEK - 5); // still before vesting lock.start

        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient), TOKEN_100K); // claims available tokens

        assertEq(IERC20(testToken).balanceOf(lock.vault), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);
        lock = govNFT.locks(tokenId);
        assertEq(lock.totalClaimed, 0);
    }

    function test_NoClaimedRewardsBeforeCliff() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            uint40(block.timestamp) + WEEK,
            uint40(block.timestamp) + WEEK * 3,
            WEEK * 2
        );
        IGovNFT.Lock memory lock = govNFT.locks(tokenId);

        skip(WEEK * 3 - 1); // still before cliff end

        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient), TOKEN_100K); // claims available tokens

        lock = govNFT.locks(tokenId);
        assertEq(IERC20(testToken).balanceOf(lock.vault), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);
        assertEq(lock.totalClaimed, 0);

        skip(1); // cliff ends
        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient), TOKEN_100K); // claims available tokens

        lock = govNFT.locks(tokenId);
        assertEq(IERC20(testToken).balanceOf(lock.vault), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), TOKEN_100K);
        assertEq(lock.totalClaimed, TOKEN_100K);
    }

    function test_ClaimPermissions() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            uint40(block.timestamp),
            uint40(block.timestamp) + WEEK * 2,
            WEEK
        );

        skip(WEEK * 2); // skip to the end of vesting

        address approvedUser = makeAddr("alice");
        assertEq(IERC20(testToken).balanceOf(approvedUser), 0);

        vm.prank(address(recipient));
        govNFT.approve(approvedUser, tokenId);

        // can claim after getting approval on nft
        vm.prank(approvedUser);
        vm.expectEmit(true, true, false, true, address(govNFT));
        emit IGovNFT.Claim({tokenId: tokenId, recipient: approvedUser, claimed: TOKEN_1});
        govNFT.claim(tokenId, approvedUser, TOKEN_1);
        assertEq(IERC20(testToken).balanceOf(approvedUser), TOKEN_1);

        address approvedForAllUser = makeAddr("bob");
        assertEq(IERC20(testToken).balanceOf(approvedForAllUser), 0);

        vm.prank(address(recipient));
        govNFT.setApprovalForAll(approvedForAllUser, true);

        // can claim after getting approval for all nfts
        vm.prank(approvedForAllUser);
        vm.expectEmit(true, true, false, true, address(govNFT));
        emit IGovNFT.Claim({tokenId: tokenId, recipient: approvedForAllUser, claimed: TOKEN_1});
        govNFT.claim(tokenId, approvedForAllUser, TOKEN_1);
        assertEq(IERC20(testToken).balanceOf(approvedForAllUser), TOKEN_1);
    }

    function test_RevertIf_ClaimIfNotRecipientOrApproved() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        address testUser = makeAddr("alice");
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            uint40(block.timestamp),
            uint40(block.timestamp) + WEEK * 2,
            WEEK
        );

        vm.prank(testUser);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, testUser, tokenId));
        govNFT.claim(tokenId, address(admin), TOKEN_100K);

        vm.prank(address(admin));
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(admin), tokenId)
        );
        govNFT.claim(tokenId, address(admin), TOKEN_100K);
    }

    function test_RevertIf_ClaimNonExistentToken() public {
        uint256 tokenId = 1;
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient), TOKEN_100K);
    }

    function test_RevertIf_ClaimToZeroAddress() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            uint40(block.timestamp),
            uint40(block.timestamp) + WEEK * 2,
            WEEK
        );

        vm.expectRevert(IGovNFT.ZeroAddress.selector);
        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(0), TOKEN_100K);
    }

    function test_LockedUnclaimed() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            uint40(block.timestamp),
            uint40(block.timestamp) + WEEK * 2,
            WEEK
        );
        IGovNFT.Lock memory lock = govNFT.locks(tokenId);

        assertEq(govNFT.locked(tokenId), lock.totalLocked);
        assertEq(govNFT.unclaimed(tokenId), 0);

        skip(lock.cliffLength - 1); // skip first week, to before end of cliff
        assertEq(govNFT.locked(tokenId), lock.totalLocked);
        assertEq(govNFT.unclaimed(tokenId), 0);

        skip(1); // skip to end of cliff
        assertEq(govNFT.locked(tokenId), lock.totalLocked / 2);
        assertEq(govNFT.unclaimed(tokenId), lock.totalLocked / 2); // one out of two weeks have passed, half of rewards available

        skip(WEEK); // skip last week of vesting
        assertEq(uint40(block.timestamp), lock.end);
        assertEq(govNFT.locked(tokenId), 0);
        lock = govNFT.locks(tokenId);
        assertEq(lock.totalClaimed, 0);
        assertEq(govNFT.unclaimed(tokenId), lock.totalLocked); // all rewards available

        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient), lock.totalLocked / 2);

        assertEq(govNFT.locked(tokenId), 0);
        assertEq(govNFT.unclaimed(tokenId), lock.totalLocked / 2);
        lock = govNFT.locks(tokenId);
        assertEq(lock.totalClaimed, lock.totalLocked / 2); // half of rewards were claimed

        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient), TOKEN_100K);

        assertEq(govNFT.locked(tokenId), 0);
        assertEq(govNFT.unclaimed(tokenId), 0);
        lock = govNFT.locks(tokenId);
        assertEq(lock.totalClaimed, lock.totalLocked); // all rewards were claimed
    }
}
