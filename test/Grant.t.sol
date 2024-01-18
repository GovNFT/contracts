// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {BaseTest} from "test/utils/BaseTest.sol";

import "src/GovNFT.sol";
import "src/Vault.sol";

contract LockTest is BaseTest {
    event Create(uint256 indexed tokenId, address indexed recipient, address indexed token, uint256 amount);

    function testCreateLock() public {
        assertEq(govNFT.totalSupply(), 0);
        assertEq(govNFT.balanceOf(address(recipient)), 0);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);

        admin.approve(testToken, address(govNFT), TOKEN_100K);

        vm.expectEmit(true, true, true, true, address(govNFT));
        emit Create(1, address(recipient), testToken, TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock(
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

        assertEq(govNFT.ownerOf(tokenId), address(recipient));

        (, , uint256 totalClaimed, , , , , , , , ) = govNFT.locks(tokenId);
        assertEq(totalClaimed, 0);

        (
            uint256 totalLocked,
            uint256 deposited,
            ,
            ,
            ,
            uint256 cliffLength,
            uint256 start,
            uint256 end,
            address token,
            address vault,
            address minter
        ) = govNFT.locks(tokenId);

        assertEq(Vault(vault).token(), address(testToken));
        assertEq(token, address(testToken));

        assertEq(cliffLength, WEEK);
        assertEq(start, block.timestamp);
        assertEq(end, block.timestamp + WEEK * 2);
        assertEq(totalLocked, TOKEN_100K);
        assertEq(deposited, TOKEN_100K);
        assertEq(minter, address(admin));

        assertEq(IERC20(testToken).balanceOf(vault), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
    }

    function testCannotCreateLockIfZeroAddress() public {
        vm.expectRevert(IGovNFT.ZeroAddress.selector);
        govNFT.createLock(address(0), address(recipient), TOKEN_1, block.timestamp, block.timestamp + WEEK * 2, WEEK);

        vm.expectRevert(IGovNFT.ZeroAddress.selector);
        govNFT.createLock(testToken, address(0), TOKEN_1, block.timestamp, block.timestamp + WEEK * 2, WEEK);
    }

    function testCannotCreateLockIfZeroAmount() public {
        vm.expectRevert(IGovNFT.ZeroAmount.selector);
        govNFT.createLock(testToken, address(recipient), 0, block.timestamp, block.timestamp + WEEK * 2, WEEK);
    }

    function testCannotCreateLockIfInvalidCliff() public {
        vm.expectRevert(IGovNFT.InvalidCliff.selector);
        govNFT.createLock(testToken, address(recipient), TOKEN_1, block.timestamp, block.timestamp + WEEK - 1, WEEK);
    }

    function testCannotCreateLockWithZeroDuration() public {
        vm.expectRevert(IGovNFT.EndBeforeOrEqualStart.selector);
        govNFT.createLock(testToken, address(recipient), TOKEN_1, block.timestamp + WEEK, block.timestamp + WEEK, WEEK);
    }

    function testCannotCreateLockIfEndBeforeStart() public {
        vm.expectRevert(IGovNFT.EndBeforeOrEqualStart.selector);
        govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_1,
            block.timestamp + WEEK * 2,
            block.timestamp + WEEK,
            WEEK
        );

        vm.expectRevert(IGovNFT.EndBeforeOrEqualStart.selector);
        govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_1,
            block.timestamp + WEEK + 1,
            block.timestamp + WEEK,
            WEEK
        );
    }

    function testCannotCreateLockIfStartIsInPast() public {
        vm.expectRevert(IGovNFT.VestingStartTooOld.selector);
        govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_1,
            block.timestamp - 1,
            block.timestamp + WEEK * 2,
            WEEK
        );
    }
}
