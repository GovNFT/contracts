// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {IERC721Errors} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import {BaseTest, IERC20} from "test/utils/BaseTest.sol";

import "src/GovNFT.sol";

contract ClaimTest is BaseTest {
    event Claim(uint256 indexed tokenId, address indexed recipient, uint256 claimed);

    function testClaimFull() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 2,
            WEEK
        );

        (uint256 totalLocked, , uint256 totalClaimed, , , , , , , address vault, ) = govNFT.locks(tokenId);

        assertEq(IERC20(testToken).balanceOf(vault), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);
        assertEq(govNFT.locked(tokenId), totalLocked);
        assertEq(totalClaimed, 0);
        assertEq(govNFT.unclaimed(tokenId), 0);

        skip(WEEK * 2); //skip to the vesting end timestamp

        (, , totalClaimed, , , , , , , , ) = govNFT.locks(tokenId);
        assertEq(govNFT.unclaimed(tokenId), totalLocked);
        assertEq(totalClaimed, 0);
        assertEq(govNFT.locked(tokenId), 0);

        vm.expectEmit(true, true, false, true, address(govNFT));
        emit Claim(tokenId, address(recipient), totalLocked);
        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient), totalLocked);

        (, , totalClaimed, , , , , , , , ) = govNFT.locks(tokenId);
        assertEq(govNFT.locked(tokenId), 0);
        assertEq(govNFT.unclaimed(tokenId), 0);
        assertEq(totalClaimed, totalLocked);
        assertEq(IERC20(testToken).balanceOf(vault), 0);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), totalLocked);
    }

    function testClaimBeneficiary() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 2,
            WEEK
        );
        address beneficiary = makeAddr("alice");

        (uint256 totalLocked, , , , , , , , , , ) = govNFT.locks(tokenId);

        skip(WEEK * 2);
        vm.prank(address(recipient));
        vm.expectEmit(true, true, false, true, address(govNFT));
        emit Claim(tokenId, beneficiary, totalLocked);
        govNFT.claim(tokenId, beneficiary, totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(beneficiary), totalLocked);
    }

    function testClaimLess() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 2,
            WEEK
        );

        (uint256 totalLocked, , , , , , , , , address vault, ) = govNFT.locks(tokenId);

        skip(WEEK * 2);
        assertEq(govNFT.unclaimed(tokenId), totalLocked);
        address beneficiary = makeAddr("alice");
        address beneficiary2 = makeAddr("bob");

        vm.prank(address(recipient));
        vm.expectEmit(true, true, false, true, address(govNFT));
        emit Claim(tokenId, beneficiary, totalLocked / 10);
        govNFT.claim(tokenId, beneficiary, totalLocked / 10);

        (, , uint256 totalClaimed, , , , , , , , ) = govNFT.locks(tokenId);
        assertEq(govNFT.unclaimed(tokenId), (9 * totalLocked) / 10);
        assertEq(totalClaimed, totalLocked / 10);
        assertEq(IERC20(testToken).balanceOf(beneficiary), totalLocked / 10);
        assertEq(IERC20(testToken).balanceOf(vault), (totalLocked * 9) / 10);

        vm.prank(address(recipient));
        vm.expectEmit(true, true, false, true, address(govNFT));
        emit Claim(tokenId, beneficiary2, totalLocked / 10);
        govNFT.claim(tokenId, beneficiary2, totalLocked / 10);

        (, , totalClaimed, , , , , , , , ) = govNFT.locks(tokenId);
        assertEq(govNFT.unclaimed(tokenId), (8 * totalLocked) / 10);
        assertEq(totalClaimed, (2 * totalLocked) / 10);
        assertEq(IERC20(testToken).balanceOf(beneficiary2), totalLocked / 10);
        assertEq(IERC20(testToken).balanceOf(vault), (totalLocked * 8) / 10);

        vm.prank(address(recipient));
        vm.expectEmit(true, true, false, true, address(govNFT));
        emit Claim(tokenId, address(recipient), (totalLocked / 10) * 8);
        govNFT.claim(tokenId, address(recipient), totalLocked); // claims remaining tokens

        (, , totalClaimed, , , , , , , , ) = govNFT.locks(tokenId);
        assertEq(govNFT.unclaimed(tokenId), 0);
        assertEq(totalClaimed, totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(vault), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), (8 * totalLocked) / 10);
    }

    function testFuzzClaimPartial(uint32 _timeskip) public {
        uint256 _start = block.timestamp;
        uint256 _end = _start + WEEK * 6;
        uint256 timeskip = uint256(_timeskip);
        timeskip = bound(timeskip, 0, _end - _start);
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock(testToken, address(recipient), TOKEN_100K, _start, _end, 0);

        (uint256 totalLocked, , , , , , uint256 start, uint256 end, , address vault, ) = govNFT.locks(tokenId);

        skip(timeskip);

        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient), totalLocked); // claims available tokens
        uint256 expectedAmount = Math.min((totalLocked * (block.timestamp - start)) / (end - start), totalLocked);

        (, , uint256 totalClaimed, , , , , , , , ) = govNFT.locks(tokenId);
        assertEq(IERC20(testToken).balanceOf(vault), totalLocked - expectedAmount);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), expectedAmount);
        assertEq(totalClaimed, expectedAmount);
        assertEq(govNFT.unclaimed(tokenId), 0);
    }

    function testFuzzMultipleClaims(uint8 _cycles) public {
        vm.assume(_cycles > 0);
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 2,
            0
        );
        (uint256 totalLocked, , , , , , uint256 start, uint256 end, , address vault, ) = govNFT.locks(tokenId);
        IERC20 token = IERC20(testToken);

        uint256 duration = end - start;
        uint256 cycles = uint256(_cycles);

        uint256 govBalance = token.balanceOf(vault);
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

            (, , uint256 totalClaimed, , , , , , , , ) = govNFT.locks(tokenId);
            govNFT.claim(tokenId, address(recipient), totalLocked); // claims available tokens
            uint256 expectedAmount = ((totalLocked * (block.timestamp - start)) / (end - start)) - totalClaimed;

            // assert balance transferred from govnft
            uint256 newBalance = token.balanceOf(vault);
            assertEq(newBalance, govBalance - expectedAmount);
            govBalance = newBalance;

            // assert balance received from recipient
            newBalance = token.balanceOf(address(recipient));
            assertEq(newBalance, balance + expectedAmount);
            balance = newBalance;
        }
        vm.stopPrank();
        assertEq(token.balanceOf(address(recipient)), totalLocked);
        assertEq(token.balanceOf(vault), 0);
        assertEq(token.balanceOf(address(govNFT)), 0);
    }

    function testNoClaimedRewardsBeforeStart() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp + WEEK,
            block.timestamp + WEEK * 3,
            WEEK
        );
        (, , , , , , , , , address vault, ) = govNFT.locks(tokenId);

        skip(WEEK - 5); // still before vesting start

        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient), TOKEN_100K); // claims available tokens

        assertEq(IERC20(testToken).balanceOf(vault), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);
        (, , uint256 totalClaimed, , , , , , , , ) = govNFT.locks(tokenId);
        assertEq(totalClaimed, 0);
    }

    function testNoClaimedRewardsBeforeCliff() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp + WEEK,
            block.timestamp + WEEK * 3,
            WEEK * 2
        );
        (, , , , , , , , , address vault, ) = govNFT.locks(tokenId);

        skip(WEEK * 3 - 1); // still before cliff end

        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient), TOKEN_100K); // claims available tokens

        (, , uint256 totalClaimed, , , , , , , , ) = govNFT.locks(tokenId);
        assertEq(IERC20(testToken).balanceOf(vault), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);
        assertEq(totalClaimed, 0);

        skip(1); // cliff ends
        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient), TOKEN_100K); // claims available tokens

        (, , totalClaimed, , , , , , , , ) = govNFT.locks(tokenId);
        assertEq(IERC20(testToken).balanceOf(vault), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), TOKEN_100K);
        assertEq(totalClaimed, TOKEN_100K);
    }

    function testClaimPermissions() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 2,
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
        emit Claim(tokenId, approvedUser, TOKEN_1);
        govNFT.claim(tokenId, approvedUser, TOKEN_1);
        assertEq(IERC20(testToken).balanceOf(approvedUser), TOKEN_1);

        address approvedForAllUser = makeAddr("bob");
        assertEq(IERC20(testToken).balanceOf(approvedForAllUser), 0);

        vm.prank(address(recipient));
        govNFT.setApprovalForAll(approvedForAllUser, true);

        // can claim after getting approval for all nfts
        vm.prank(approvedForAllUser);
        vm.expectEmit(true, true, false, true, address(govNFT));
        emit Claim(tokenId, approvedForAllUser, TOKEN_1);
        govNFT.claim(tokenId, approvedForAllUser, TOKEN_1);
        assertEq(IERC20(testToken).balanceOf(approvedForAllUser), TOKEN_1);
    }

    function testCannotClaimIfNotRecipientOrApproved() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        address testUser = makeAddr("alice");
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 2,
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

    function testCannotClaimNonExistentToken() public {
        uint256 tokenId = 1;
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient), TOKEN_100K);
    }

    function testCannotClaimToZeroAddress() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 2,
            WEEK
        );

        vm.expectRevert(IGovNFT.ZeroAddress.selector);
        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(0), TOKEN_100K);
    }

    function testLockedUnclaimed() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 2,
            WEEK
        );
        (uint256 totalLocked, , , , , uint256 cliffLength, , uint256 end, , , ) = govNFT.locks(tokenId);

        assertEq(govNFT.locked(tokenId), totalLocked);
        assertEq(govNFT.unclaimed(tokenId), 0);

        skip(cliffLength - 1); // skip first week, to before end of cliff
        assertEq(govNFT.locked(tokenId), totalLocked);
        assertEq(govNFT.unclaimed(tokenId), 0);

        skip(1); // skip to end of cliff
        assertEq(govNFT.locked(tokenId), totalLocked / 2);
        assertEq(govNFT.unclaimed(tokenId), totalLocked / 2); // one out of two weeks have passed, half of rewards available

        skip(WEEK); // skip last week of vesting
        assertEq(block.timestamp, end);
        assertEq(govNFT.locked(tokenId), 0);
        (, , uint256 totalClaimed, , , , , , , , ) = govNFT.locks(tokenId);
        assertEq(totalClaimed, 0);
        assertEq(govNFT.unclaimed(tokenId), totalLocked); // all rewards available

        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient), totalLocked / 2);

        assertEq(govNFT.locked(tokenId), 0);
        assertEq(govNFT.unclaimed(tokenId), totalLocked / 2);
        (, , totalClaimed, , , , , , , , ) = govNFT.locks(tokenId);
        assertEq(totalClaimed, totalLocked / 2); // half of rewards were claimed

        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient), TOKEN_100K);

        assertEq(govNFT.locked(tokenId), 0);
        assertEq(govNFT.unclaimed(tokenId), 0);
        (, , totalClaimed, , , , , , , , ) = govNFT.locks(tokenId);
        assertEq(totalClaimed, totalLocked); // all rewards were claimed
    }
}
