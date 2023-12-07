// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {BaseTest} from "test/utils/BaseTest.sol";

import "src/VestingEscrow.sol";
import "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC721Errors} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract DelegateTest is BaseTest {
    event Delegate(uint256 indexed tokenId, address delegate);

    address testAddr;
    uint256 tokenId;

    function _setUp() public override {
        admin.approve(testGovernanceToken, address(govNFT), TOKEN_100K);
        testAddr = makeAddr("alice");
        vm.prank(address(admin));
        tokenId = govNFT.createGrant(
            testGovernanceToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 2,
            WEEK
        );
    }

    function testDelegate() public {
        assertEq(IVotes(testGovernanceToken).delegates(address(admin)), address(0));
        assertEq(IVotes(testGovernanceToken).delegates(address(recipient)), address(0));

        assertEq(IVotes(testGovernanceToken).getVotes(address(testAddr)), 0);

        vm.expectEmit(true, false, false, true, address(govNFT));
        emit Delegate(tokenId, testAddr);
        vm.prank(address(recipient));
        govNFT.delegate(tokenId, address(testAddr));

        address vault = address(govNFT.idToVault(tokenId));
        assertEq(IVotes(testGovernanceToken).delegates(address(recipient)), address(0));
        assertEq(IVotes(testGovernanceToken).delegates(address(admin)), address(0));
        assertEq(IVotes(testGovernanceToken).delegates(vault), testAddr);
        assertEq(IVotes(testGovernanceToken).getVotes(address(testAddr)), TOKEN_100K);
    }

    function testDelegateCoupleGrantsWithSameToken() public {
        address recipient1 = address(recipient);
        address recipient2 = makeAddr("recipient2");
        deal(testGovernanceToken, address(admin), TOKEN_100K);
        admin.approve(testGovernanceToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId2 = govNFT.createGrant(
            testGovernanceToken,
            recipient2,
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 2,
            WEEK
        );

        assertEq(IVotes(testGovernanceToken).delegates(address(admin)), address(0));
        assertEq(IVotes(testGovernanceToken).delegates(recipient1), address(0));
        assertEq(IVotes(testGovernanceToken).delegates(recipient2), address(0));

        assertEq(IVotes(testGovernanceToken).getVotes(address(admin)), 0);
        assertEq(IVotes(testGovernanceToken).getVotes(recipient1), 0);
        assertEq(IVotes(testGovernanceToken).getVotes(recipient2), 0);

        vm.prank(recipient1);
        govNFT.delegate(tokenId, recipient1);

        vm.prank(recipient2);
        govNFT.delegate(tokenId2, recipient2);

        assertEq(IVotes(testGovernanceToken).getVotes(address(admin)), 0);
        assertEq(IVotes(testGovernanceToken).getVotes(recipient1), TOKEN_100K);
        assertEq(IVotes(testGovernanceToken).getVotes(recipient2), TOKEN_100K);

        vm.prank(recipient1);
        govNFT.delegate(tokenId, recipient2);

        assertEq(IVotes(testGovernanceToken).getVotes(address(admin)), 0);
        assertEq(IVotes(testGovernanceToken).getVotes(recipient1), 0);
        assertEq(IVotes(testGovernanceToken).getVotes(recipient2), 2 * TOKEN_100K);
    }

    function testCannotDelegateIfTokenDoesNotSupport() public {
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
        vm.expectRevert();
        vm.prank(address(recipient));
        govNFT.delegate(tokenId, testAddr);
    }

    function testCannotDelegateIfNotRecipient() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, testAddr, tokenId));
        vm.prank(address(testAddr));
        govNFT.delegate(tokenId, testAddr);
    }

    function testCannotDelegateToZeroAddress() public {
        vm.expectRevert(IVestingEscrow.ZeroAddress.selector);
        vm.prank(address(recipient));
        govNFT.delegate(tokenId, address(0));
    }
}