// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {IERC721Errors} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import {BaseTest} from "test/utils/BaseTest.sol";
import {MockERC20} from "test/utils/MockERC20.sol";

import "src/VestingEscrow.sol";

contract SweepTest is BaseTest {
    event Sweep(uint256 indexed tokenId, address indexed token, address indexed receiver, uint256 amount);

    uint256 tokenId;
    address vault;

    function _setUp() public override {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        tokenId = govNFT.createGrant(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 2,
            WEEK
        );

        vault = address(govNFT.idToVault(tokenId));

        //airdrop 100K tokens to the govNFT's vault
        airdropper.transfer(airdropToken, vault, TOKEN_100K);
    }

    function testSweepFull() public {
        assertEq(IERC20(airdropToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(airdropToken).balanceOf(vault), TOKEN_100K);
        assertEq(IERC20(airdropToken).balanceOf(address(admin)), 0);
        assertEq(IERC20(airdropToken).balanceOf(address(recipient)), 0);

        vm.prank(address(recipient));
        vm.expectEmit(true, true, true, true, address(govNFT));
        emit Sweep(tokenId, airdropToken, address(recipient), TOKEN_100K);
        govNFT.sweep(tokenId, airdropToken, address(recipient));

        assertEq(IERC20(airdropToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(airdropToken).balanceOf(vault), 0);
        assertEq(IERC20(airdropToken).balanceOf(address(admin)), 0);
        assertEq(IERC20(airdropToken).balanceOf(address(recipient)), TOKEN_100K);
    }

    function testSweepFullAirdropTokenSameAsGrantToken() public {
        //airdrop 100K grant tokens (as airdrop) to the govNFT's vault
        airdropper.transfer(testToken, vault, TOKEN_100K);

        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(vault), 2 * TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(address(admin)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        vm.prank(address(recipient));
        vm.expectEmit(true, true, true, true, address(govNFT));
        emit Sweep(tokenId, testToken, address(recipient), TOKEN_100K);
        govNFT.sweep(tokenId, testToken, address(recipient), TOKEN_100K);

        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(vault), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(address(admin)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), TOKEN_100K);
    }

    function testSweepToDifferentRecipient() public {
        address testUser = address(0x123);
        assertEq(IERC20(airdropToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(airdropToken).balanceOf(vault), TOKEN_100K);
        assertEq(IERC20(airdropToken).balanceOf(address(admin)), 0);
        assertEq(IERC20(airdropToken).balanceOf(address(recipient)), 0);
        assertEq(IERC20(airdropToken).balanceOf(testUser), 0);

        vm.prank(address(recipient));
        vm.expectEmit(true, true, true, true, address(govNFT));
        emit Sweep(tokenId, airdropToken, testUser, TOKEN_100K);
        govNFT.sweep(tokenId, airdropToken, testUser);

        assertEq(IERC20(airdropToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(airdropToken).balanceOf(vault), 0);
        assertEq(IERC20(airdropToken).balanceOf(address(admin)), 0);
        assertEq(IERC20(airdropToken).balanceOf(address(recipient)), 0);
        assertEq(IERC20(airdropToken).balanceOf(testUser), TOKEN_100K);
    }

    function testFuzzSweepPartial(uint256 amount) public {
        amount = bound(amount, 1, TOKEN_100K);
        uint256 amountLeftToSweep = TOKEN_100K;

        uint256 amountSwept;
        uint256 cycles; //prevent long running tests
        while (amountLeftToSweep > 0 && cycles < 500) {
            if (amount > amountLeftToSweep) amount = amountLeftToSweep;
            amountSwept += amount;

            vm.prank(address(recipient));
            vm.expectEmit(true, true, true, true, address(govNFT));
            emit Sweep(tokenId, airdropToken, address(recipient), amount);
            govNFT.sweep(tokenId, airdropToken, address(recipient), amount);

            assertEq(IERC20(airdropToken).balanceOf(address(recipient)), amountSwept);
            assertEq(IERC20(airdropToken).balanceOf(vault), TOKEN_100K - amountSwept);

            amountLeftToSweep -= amount;
            cycles++;
        }
        assertEq(IERC20(airdropToken).balanceOf(address(recipient)), amountSwept);
        assertEq(IERC20(airdropToken).balanceOf(vault), TOKEN_100K - amountSwept);
    }

    function testFuzzMultipleFullSweepsDontAffectGrantWhenAirdropTokenSameAsGrant(
        uint32 _timeskip,
        uint8 cycles
    ) public {
        uint256 _start = block.timestamp;
        uint256 _end = _start + WEEK * 6;
        uint256 timeskip = uint256(_timeskip);
        timeskip = bound(timeskip, 0, _end - _start);

        (uint256 totalLocked, uint256 cliff, uint256 start, uint256 end) = govNFT.grants(tokenId);

        uint256 expectedClaim;
        uint256 balanceRecipient;
        skip(cliff);
        for (uint256 i = 0; i <= cycles; i++) {
            deal(testToken, address(airdropper), TOKEN_100K);
            //airdrop amount
            airdropper.transfer(testToken, vault, TOKEN_100K);
            skip(timeskip);
            expectedClaim = Math.min((totalLocked * (block.timestamp - start)) / (end - start), totalLocked);

            //full sweep
            vm.prank(address(recipient));
            govNFT.sweep(tokenId, testToken, address(recipient));
            balanceRecipient += TOKEN_100K;

            vm.prank(address(recipient));
            govNFT.claim(tokenId, address(recipient), totalLocked);

            assertEq(IERC20(testToken).balanceOf(vault), totalLocked - expectedClaim);
            assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
            assertEq(IERC20(testToken).balanceOf(address(recipient)), balanceRecipient + expectedClaim);
            assertEq(govNFT.totalClaimed(tokenId), expectedClaim);
            assertEq(govNFT.unclaimed(tokenId), 0);
        }
    }

    function testFuzzPartialSweepDoesntAffectGrantWhenAirdropTokenSameAsGrant(uint32 _timeskip, uint256 amount) public {
        amount = bound(amount, 1, TOKEN_100K);
        //airdrop amount
        airdropper.transfer(testToken, vault, TOKEN_100K);
        uint256 _start = block.timestamp;
        uint256 _end = _start + WEEK * 6;
        uint256 timeskip = uint256(_timeskip);
        timeskip = bound(timeskip, 0, _end - _start);

        (uint256 totalLocked, uint256 cliff, uint256 start, uint256 end) = govNFT.grants(tokenId);

        skip(timeskip + cliff);
        uint256 expectedClaim = Math.min((totalLocked * (block.timestamp - start)) / (end - start), totalLocked);

        vm.prank(address(recipient));
        govNFT.sweep(tokenId, testToken, address(recipient), amount);

        assertEq(IERC20(testToken).balanceOf(vault), totalLocked + TOKEN_100K - amount);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), amount);
        assertEq(govNFT.totalClaimed(tokenId), 0);
        assertEq(govNFT.unclaimed(tokenId), expectedClaim);

        //check user can stil claim grant
        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient), totalLocked);

        assertEq(IERC20(testToken).balanceOf(vault), totalLocked + TOKEN_100K - expectedClaim - amount);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), amount + expectedClaim);
        assertEq(govNFT.totalClaimed(tokenId), expectedClaim);
        assertEq(govNFT.unclaimed(tokenId), 0);
    }

    function testSweepAfterClaim() public {
        airdropper.transfer(testToken, vault, TOKEN_100K);
        (uint256 totalLocked, , , ) = govNFT.grants(tokenId);

        skip(WEEK * 2); //skip to the vesting end timestamp

        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient));

        assertEq(IERC20(testToken).balanceOf(vault), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), TOKEN_100K);
        assertEq(govNFT.totalClaimed(tokenId), totalLocked);
        assertEq(govNFT.unclaimed(tokenId), 0);

        vm.prank(address(recipient));
        govNFT.sweep(tokenId, testToken, address(recipient));

        assertEq(IERC20(testToken).balanceOf(vault), 0);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 2 * TOKEN_100K);
        assertEq(govNFT.totalClaimed(tokenId), totalLocked);
        assertEq(govNFT.unclaimed(tokenId), 0);
    }

    function testSweepPermissions() public {
        address approvedUser = makeAddr("alice");
        assertEq(IERC20(airdropToken).balanceOf(approvedUser), 0);

        vm.prank(address(recipient));
        govNFT.approve(approvedUser, tokenId);

        // can sweep after getting approval on nft
        vm.prank(approvedUser);
        vm.expectEmit(true, true, true, true, address(govNFT));
        emit Sweep(tokenId, airdropToken, approvedUser, TOKEN_1);
        govNFT.sweep(tokenId, airdropToken, approvedUser, TOKEN_1);
        assertEq(IERC20(airdropToken).balanceOf(approvedUser), TOKEN_1);

        address approvedForAllUser = makeAddr("bob");
        assertEq(IERC20(testToken).balanceOf(approvedForAllUser), 0);

        vm.prank(address(recipient));
        govNFT.setApprovalForAll(approvedForAllUser, true);

        // can sweep after getting approval for all nfts
        vm.prank(approvedForAllUser);
        vm.expectEmit(true, true, true, true, address(govNFT));
        emit Sweep(tokenId, airdropToken, approvedForAllUser, TOKEN_1);
        govNFT.sweep(tokenId, airdropToken, approvedForAllUser, TOKEN_1);
        assertEq(IERC20(airdropToken).balanceOf(approvedForAllUser), TOKEN_1);
    }

    function testCannotSweepIfNotRecipientOrApproved() public {
        address testUser = address(0x123);
        vm.prank(testUser);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, testUser, tokenId));
        govNFT.sweep(tokenId, airdropToken, address(admin));

        vm.prank(address(admin));
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(admin), tokenId)
        );
        govNFT.sweep(tokenId, airdropToken, address(admin));
    }

    function testCannotSweepNonExistentToken() public {
        tokenId = 3;
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
        vm.prank(address(recipient));
        govNFT.sweep(tokenId, airdropToken, address(recipient));
    }

    function testCannotSweepIfNoAirdrop() public {
        testToken = address(new MockERC20("", "", 18));
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(vault), 0);
        assertEq(IERC20(testToken).balanceOf(address(admin)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        vm.expectRevert(IVestingEscrow.ZeroAmount.selector);
        vm.prank(address(recipient));
        govNFT.sweep(tokenId, testToken, address(recipient));

        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(vault), 0);
        assertEq(IERC20(testToken).balanceOf(address(admin)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);
    }

    function testCannotSweepToZeroAddress() public {
        vm.expectRevert(IVestingEscrow.ZeroAddress.selector);
        vm.prank(address(recipient));
        govNFT.sweep(tokenId, airdropToken, address(0));
    }
}
