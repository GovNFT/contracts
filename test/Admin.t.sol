// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {BaseTest} from "test/utils/BaseTest.sol";

import "src/VestingEscrow.sol";

contract AdminTest is BaseTest {
    event SetAdmin(uint256 indexed tokenId, address admin);
    event AcceptAdmin(uint256 indexed tokenId, address admin);

    address testAddr;
    uint256 tokenId;

    function _setUp() public override {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        testAddr = makeAddr("alice");
        vm.prank(address(admin));
        tokenId = govNFT.createGrant(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 2,
            WEEK
        );
    }

    function testSetAdmin() public {
        assertEq(govNFT.idToAdmin(tokenId), address(admin));
        assertEq(govNFT.idToPendingAdmin(tokenId), address(0));

        vm.expectEmit(true, false, false, true, address(govNFT));
        emit SetAdmin(tokenId, testAddr);
        vm.prank(address(admin));
        govNFT.setAdmin(tokenId, testAddr);

        assertEq(govNFT.idToAdmin(tokenId), address(admin));
        assertEq(govNFT.idToPendingAdmin(tokenId), testAddr);
    }

    function testCannotSetAdminIfZeroAddress() public {
        vm.expectRevert(IVestingEscrow.ZeroAddress.selector);
        vm.prank(address(admin));
        govNFT.setAdmin(tokenId, address(0));
    }

    function testCannotSetAdminIfNotAdmin() public {
        vm.expectRevert(IVestingEscrow.NotAdmin.selector);
        vm.prank(address(testAddr));
        govNFT.setAdmin(tokenId, testAddr);

        vm.expectRevert(IVestingEscrow.NotAdmin.selector);
        vm.prank(address(recipient));
        govNFT.setAdmin(tokenId, testAddr);
    }

    function testAcceptAdmin() public {
        vm.prank(address(admin));
        govNFT.setAdmin(tokenId, testAddr);

        assertEq(govNFT.idToAdmin(tokenId), address(admin));
        assertEq(govNFT.idToPendingAdmin(tokenId), address(testAddr));

        vm.expectEmit(true, false, false, true, address(govNFT));
        emit AcceptAdmin(tokenId, testAddr);
        vm.prank(testAddr);
        govNFT.acceptAdmin(tokenId);

        assertEq(govNFT.idToAdmin(tokenId), testAddr);
        assertEq(govNFT.idToPendingAdmin(tokenId), address(0));
    }

    function testCannotAcceptAdminIfPendingAdminNotSet() public {
        assertEq(govNFT.idToPendingAdmin(tokenId), address(0));
        vm.expectRevert(IVestingEscrow.NotPendingAdmin.selector);
        vm.prank(address(recipient));
        govNFT.acceptAdmin(tokenId);
    }

    function testCannotAcceptAdminIfNotPendingAdmin() public {
        vm.prank(address(admin));
        govNFT.setAdmin(tokenId, testAddr);

        vm.expectRevert(IVestingEscrow.NotPendingAdmin.selector);
        vm.prank(address(recipient));
        govNFT.acceptAdmin(tokenId);

        vm.expectRevert(IVestingEscrow.NotPendingAdmin.selector);
        vm.prank(address(admin));
        govNFT.acceptAdmin(tokenId);
    }

    function testRenounceAdmin() public {
        deal(testToken, address(admin), 2 * TOKEN_100K);
        admin.approve(testToken, address(govNFT), 2 * TOKEN_100K);

        vm.startPrank(address(admin));
        uint256 tokenId2 = govNFT.createGrant(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 2,
            WEEK
        );
        govNFT.setAdmin(tokenId2, testAddr);

        assertEq(govNFT.idToAdmin(tokenId), address(admin));
        assertEq(govNFT.idToAdmin(tokenId2), address(admin));
        assertEq(govNFT.idToPendingAdmin(tokenId), address(0));
        assertEq(govNFT.idToPendingAdmin(tokenId2), address(testAddr));

        vm.expectEmit(true, false, false, true, address(govNFT));
        emit AcceptAdmin(tokenId, address(0));
        govNFT.renounceAdmin(tokenId);

        vm.expectEmit(true, false, false, true, address(govNFT));
        emit AcceptAdmin(tokenId2, address(0));
        govNFT.renounceAdmin(tokenId2);

        vm.stopPrank();

        assertEq(govNFT.idToAdmin(tokenId), address(0));
        assertEq(govNFT.idToAdmin(tokenId2), address(0));
        assertEq(govNFT.idToPendingAdmin(tokenId), address(0));
        assertEq(govNFT.idToPendingAdmin(tokenId2), address(0));
    }

    function testCannotRenounceAdminIfNotAdmin() public {
        vm.expectRevert(IVestingEscrow.NotAdmin.selector);
        vm.prank(address(recipient));
        govNFT.renounceAdmin(tokenId);

        vm.expectRevert(IVestingEscrow.NotAdmin.selector);
        vm.prank(testAddr);
        govNFT.renounceAdmin(tokenId);
    }
}
