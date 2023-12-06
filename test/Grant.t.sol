// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {BaseTest} from "test/utils/BaseTest.sol";

import "src/VestingEscrow.sol";

contract GrantTest is BaseTest {
    event Fund(uint256 indexed tokenId, address indexed recipient, address indexed token, uint256 amount);

    function testCreateGrant() public {
        assertEq(govNFT.totalSupply(), 0);
        assertEq(govNFT.balanceOf(address(recipient)), 0);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);

        admin.approve(testToken, address(govNFT), TOKEN_100K);

        vm.expectEmit(true, true, true, true, address(govNFT));
        emit Fund(1, address(recipient), testToken, TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createGrant(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 2,
            WEEK
        );

        assertEq(govNFT.totalSupply(), 1);
        assertEq(govNFT.balanceOf(address(recipient)), 1);
        assertEq(govNFT.tokenOfOwnerByIndex(address(recipient), 0), tokenId);

        assertEq(govNFT.idToAdmin(tokenId), address(admin));
        assertEq(govNFT.ownerOf(tokenId), address(recipient));
        assertEq(govNFT.idToToken(tokenId), address(testToken));
        assertEq(govNFT.disabledAt(tokenId), block.timestamp + WEEK * 2);
        assertEq(govNFT.totalClaimed(tokenId), 0);

        (uint256 totalLocked, uint256 cliffLength, uint256 start, uint256 end) = govNFT.grants(tokenId);

        assertEq(cliffLength, WEEK);
        assertEq(start, block.timestamp);
        assertEq(end, block.timestamp + WEEK * 2);
        assertEq(totalLocked, TOKEN_100K);

        assertEq(IERC20(testToken).balanceOf(address(govNFT)), totalLocked);
    }

    function testCreateGrantWithDuration() public {
        assertEq(govNFT.totalSupply(), 0);
        assertEq(govNFT.balanceOf(address(recipient)), 0);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);

        admin.approve(testToken, address(govNFT), TOKEN_100K);

        vm.expectEmit(true, true, true, true, address(govNFT));
        emit Fund(1, address(recipient), testToken, TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createGrant(testToken, address(recipient), TOKEN_100K, WEEK * 2, WEEK);

        assertEq(govNFT.totalSupply(), 1);
        assertEq(govNFT.balanceOf(address(recipient)), 1);
        assertEq(govNFT.tokenOfOwnerByIndex(address(recipient), 0), tokenId);

        assertEq(govNFT.idToAdmin(tokenId), address(admin));
        assertEq(govNFT.ownerOf(tokenId), address(recipient));
        assertEq(govNFT.idToToken(tokenId), address(testToken));
        assertEq(govNFT.disabledAt(tokenId), block.timestamp + WEEK * 2);
        assertEq(govNFT.totalClaimed(tokenId), 0);

        (uint256 totalLocked, uint256 cliffLength, uint256 start, uint256 end) = govNFT.grants(tokenId);

        assertEq(cliffLength, WEEK);
        assertEq(start, block.timestamp);
        assertEq(end, block.timestamp + WEEK * 2);
        assertEq(totalLocked, TOKEN_100K);

        assertEq(IERC20(testToken).balanceOf(address(govNFT)), totalLocked);
    }

    function testCannotCreateGrantIfZeroAddress() public {
        vm.expectRevert(IVestingEscrow.ZeroAddress.selector);
        govNFT.createGrant(address(0), address(recipient), TOKEN_1, block.timestamp, block.timestamp + WEEK * 2, WEEK);

        vm.expectRevert(IVestingEscrow.ZeroAddress.selector);
        govNFT.createGrant(testToken, address(0), TOKEN_1, block.timestamp, block.timestamp + WEEK * 2, WEEK);
    }

    function testCannotCreateGrantIfZeroAmount() public {
        vm.expectRevert(IVestingEscrow.ZeroAmount.selector);
        govNFT.createGrant(testToken, address(recipient), 0, block.timestamp, block.timestamp + WEEK * 2, WEEK);
    }

    function testCannotCreateGrantIfInvalidCliff() public {
        vm.expectRevert(IVestingEscrow.InvalidCliff.selector);
        govNFT.createGrant(testToken, address(recipient), TOKEN_1, block.timestamp, block.timestamp + WEEK - 1, WEEK);

        vm.expectRevert(IVestingEscrow.InvalidCliff.selector);
        govNFT.createGrant(testToken, address(recipient), TOKEN_1, WEEK - 1, WEEK);
    }

    function testCannotCreateGrantWithZeroDuration() public {
        vm.expectRevert(IVestingEscrow.EndBeforeOrEqual.selector);
        govNFT.createGrant(
            testToken,
            address(recipient),
            TOKEN_1,
            block.timestamp + WEEK,
            block.timestamp + WEEK,
            WEEK
        );

        vm.expectRevert(IVestingEscrow.EndBeforeOrEqual.selector);
        govNFT.createGrant(testToken, address(recipient), TOKEN_1, 0, 0);
    }

    function testCannotCreateGrantIfEndBeforeStart() public {
        vm.expectRevert(IVestingEscrow.EndBeforeOrEqual.selector);
        govNFT.createGrant(
            testToken,
            address(recipient),
            TOKEN_1,
            block.timestamp + WEEK * 2,
            block.timestamp + WEEK,
            WEEK
        );

        vm.expectRevert(IVestingEscrow.EndBeforeOrEqual.selector);
        govNFT.createGrant(
            testToken,
            address(recipient),
            TOKEN_1,
            block.timestamp + WEEK + 1,
            block.timestamp + WEEK,
            WEEK
        );
    }

    function testCannotCreateGrantIfStartIsInPast() public {
        vm.expectRevert(IVestingEscrow.VestingStartTooOld.selector);
        govNFT.createGrant(
            testToken,
            address(recipient),
            TOKEN_1,
            block.timestamp - 1,
            block.timestamp + WEEK * 2,
            WEEK
        );
    }
}
