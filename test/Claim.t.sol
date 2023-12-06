// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {IERC721Errors} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import {BaseTest} from "test/utils/BaseTest.sol";

import "src/VestingEscrow.sol";

contract ClaimTest is BaseTest {
    event Claim(uint256 indexed tokenId, address indexed recipient, uint256 claimed);

    function testClaimFull() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createGrant(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 2,
            WEEK
        );

        (uint256 totalLocked, , , ) = govNFT.grants(tokenId);

        assertEq(IERC20(testToken).balanceOf(address(govNFT)), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);
        assertEq(govNFT.locked(tokenId), totalLocked);
        assertEq(govNFT.totalClaimed(tokenId), 0);
        assertEq(govNFT.unclaimed(tokenId), 0);

        skip(WEEK * 2); //skip to the vesting end timestamp
        assertEq(govNFT.unclaimed(tokenId), totalLocked);
        assertEq(govNFT.totalClaimed(tokenId), 0);
        assertEq(govNFT.locked(tokenId), 0);

        vm.expectEmit(true, true, false, true, address(govNFT));
        emit Claim(tokenId, address(recipient), totalLocked);
        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient));

        assertEq(govNFT.locked(tokenId), 0);
        assertEq(govNFT.unclaimed(tokenId), 0);
        assertEq(govNFT.totalClaimed(tokenId), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), totalLocked);
    }

    function testClaimBeneficiary() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createGrant(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 2,
            WEEK
        );
        address beneficiary = makeAddr("alice");

        (uint256 totalLocked, , , ) = govNFT.grants(tokenId);

        skip(WEEK * 2);
        vm.prank(address(recipient));
        govNFT.claim(tokenId, beneficiary);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(beneficiary), totalLocked);
    }

    function testClaimLess() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createGrant(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 2,
            WEEK
        );

        (uint256 totalLocked, , , ) = govNFT.grants(tokenId);

        skip(WEEK * 2);
        assertEq(govNFT.unclaimed(tokenId), totalLocked);
        address beneficiary = makeAddr("alice");
        address beneficiary2 = makeAddr("bob");

        vm.prank(address(recipient));
        govNFT.claim(tokenId, beneficiary, totalLocked / 10);

        assertEq(govNFT.unclaimed(tokenId), (9 * totalLocked) / 10);
        assertEq(govNFT.totalClaimed(tokenId), totalLocked / 10);
        assertEq(IERC20(testToken).balanceOf(beneficiary), totalLocked / 10);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), (totalLocked * 9) / 10);

        vm.prank(address(recipient));
        govNFT.claim(tokenId, beneficiary2, totalLocked / 10);

        assertEq(govNFT.unclaimed(tokenId), (8 * totalLocked) / 10);
        assertEq(govNFT.totalClaimed(tokenId), (2 * totalLocked) / 10);
        assertEq(IERC20(testToken).balanceOf(beneficiary2), totalLocked / 10);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), (totalLocked * 8) / 10);

        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient)); // claims remaining tokens

        assertEq(govNFT.unclaimed(tokenId), 0);
        assertEq(govNFT.totalClaimed(tokenId), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), (8 * totalLocked) / 10);
    }

    function testFuzzClaimPartial(uint32 _timeskip) public {
        uint256 _start = block.timestamp;
        uint256 _end = _start + WEEK * 6;
        uint256 timeskip = uint256(_timeskip);
        timeskip = bound(timeskip, 0, _end - _start);
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createGrant(testToken, address(recipient), TOKEN_100K, _start, _end, 0);
        (uint256 totalLocked, , uint256 start, uint256 end) = govNFT.grants(tokenId);

        skip(timeskip);

        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient)); // claims available tokens
        uint256 expectedAmount = Math.min((totalLocked * (block.timestamp - start)) / (end - start), totalLocked);

        assertEq(IERC20(testToken).balanceOf(address(govNFT)), totalLocked - expectedAmount);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), expectedAmount);
        assertEq(govNFT.totalClaimed(tokenId), expectedAmount);
        assertEq(govNFT.unclaimed(tokenId), 0);
    }

    function testFuzzMultipleClaims(uint8 _cycles) public {
        vm.assume(_cycles > 0);
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createGrant(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 2,
            0
        );
        (uint256 totalLocked, , uint256 start, uint256 end) = govNFT.grants(tokenId);
        IERC20 token = IERC20(testToken);

        uint256 duration = end - start;
        uint256 cycles = uint256(_cycles);

        uint256 govBalance = token.balanceOf(address(govNFT));
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
            uint256 totalClaimed = govNFT.totalClaimed(tokenId);
            govNFT.claim(tokenId, address(recipient)); // claims available tokens
            uint256 expectedAmount = ((totalLocked * (block.timestamp - start)) / (end - start)) - totalClaimed;

            // assert balance transferred from govnft
            uint256 newBalance = token.balanceOf(address(govNFT));
            assertEq(newBalance, govBalance - expectedAmount);
            govBalance = newBalance;

            // assert balance received from recipient
            newBalance = token.balanceOf(address(recipient));
            assertEq(newBalance, balance + expectedAmount);
            balance = newBalance;
        }
        vm.stopPrank();
        assertEq(token.balanceOf(address(recipient)), totalLocked);
        assertEq(token.balanceOf(address(govNFT)), 0);
    }

    function testNoClaimedRewardsBeforeStart() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createGrant(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp + WEEK,
            block.timestamp + WEEK * 3,
            WEEK
        );

        skip(WEEK - 5); // still before vesting start

        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient)); // claims available tokens

        assertEq(IERC20(testToken).balanceOf(address(govNFT)), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);
        assertEq(govNFT.totalClaimed(tokenId), 0);
    }

    function testClaimPermissions() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createGrant(
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
        uint256 tokenId = govNFT.createGrant(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 2,
            WEEK
        );

        vm.prank(testUser);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, testUser, tokenId));
        govNFT.claim(tokenId, address(admin));

        vm.prank(address(admin));
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(admin), tokenId)
        );
        govNFT.claim(tokenId, address(admin));
    }

    function testCannotClaimNonExistentToken() public {
        uint256 tokenId = 1;
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient));
    }

    function testCannotClaimToZeroAddress() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createGrant(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 2,
            WEEK
        );

        vm.expectRevert(IVestingEscrow.ZeroAddress.selector);
        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(0));
    }

    function testLockedUnclaimed() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createGrant(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 2,
            WEEK
        );
        (uint256 totalLocked, uint256 cliffLength, , uint256 end) = govNFT.grants(tokenId);

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
        assertEq(govNFT.totalClaimed(tokenId), 0);
        assertEq(govNFT.unclaimed(tokenId), totalLocked); // all rewards available

        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient), totalLocked / 2);

        assertEq(govNFT.locked(tokenId), 0);
        assertEq(govNFT.unclaimed(tokenId), totalLocked / 2);
        assertEq(govNFT.totalClaimed(tokenId), totalLocked / 2); // half of rewards were claimed

        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient));

        assertEq(govNFT.locked(tokenId), 0);
        assertEq(govNFT.unclaimed(tokenId), 0);
        assertEq(govNFT.totalClaimed(tokenId), totalLocked); // all rewards were claimed
    }
}
