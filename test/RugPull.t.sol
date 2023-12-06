// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {BaseTest} from "test/utils/BaseTest.sol";

import "src/VestingEscrow.sol";

contract RugPullTest is BaseTest {
    event RugPull(uint256 indexed tokenId, address recipient, uint256 rugged);

    function testRugPull() public {
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
        (uint256 totalLocked, , , uint256 end) = govNFT.grants(tokenId);

        assertEq(IERC20(testToken).balanceOf(address(govNFT)), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);
        assertEq(IERC20(testToken).balanceOf(address(admin)), 0);
        assertEq(govNFT.disabledAt(tokenId), end);

        vm.expectEmit(true, true, false, true, address(govNFT));
        emit RugPull(tokenId, address(recipient), totalLocked);
        vm.prank(address(admin));
        govNFT.rugPull(tokenId);

        assertEq(IERC20(testToken).balanceOf(address(admin)), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(govNFT.disabledAt(tokenId), block.timestamp);
    }

    function testCannotRugPullIfNotAdmin() public {
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

        address testAddr = makeAddr("alice");

        vm.expectRevert(IVestingEscrow.NotAdmin.selector);
        vm.prank(address(testAddr));
        govNFT.rugPull(tokenId);

        vm.expectRevert(IVestingEscrow.NotAdmin.selector);
        vm.prank(address(recipient));
        govNFT.rugPull(tokenId);
    }

    function testCannotRugPullAfterEndTime() public {
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

        skip(WEEK * 2); // skip to end of vesting

        vm.expectRevert(IVestingEscrow.AlreadyDisabled.selector);
        vm.prank(address(admin));
        govNFT.rugPull(tokenId);
    }

    function testRugPullBeforeStartTime() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createGrant(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp + WEEK,
            block.timestamp + WEEK * 3,
            0
        );
        (uint256 totalLocked, , , ) = govNFT.grants(tokenId);

        skip(WEEK - 1); // skip to last timestamp before vesting starts

        vm.prank(address(admin));
        govNFT.rugPull(tokenId); // all tokens rugpulled, as no tokens were vested

        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient), totalLocked);

        assertEq(IERC20(testToken).balanceOf(address(admin)), totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(govNFT.disabledAt(tokenId), block.timestamp);
    }

    function testFuzzRugPullPartiallyVested(uint32 _timeskip) public {
        uint256 _start = block.timestamp;
        uint256 _end = _start + WEEK * 6;
        uint256 timeskip = uint256(_timeskip);
        timeskip = bound(timeskip, 0, _end - _start - 1); // the grant cannot be disabled
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createGrant(testToken, address(recipient), TOKEN_100K, _start, _end, 0);
        skip(timeskip);
        (uint256 totalLocked, , uint256 start, uint256 end) = govNFT.grants(tokenId);

        uint256 expectedClaims = Math.min((totalLocked * (block.timestamp - start)) / (end - start), totalLocked);
        uint256 expectedRugPull = totalLocked - expectedClaims;

        vm.prank(address(admin));
        govNFT.rugPull(tokenId);

        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient), totalLocked);

        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(address(admin)), expectedRugPull);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), expectedClaims);
    }
}
