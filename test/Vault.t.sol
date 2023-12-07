// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {BaseTest} from "test/utils/BaseTest.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import "src/Vault.sol";

contract VaultTest is BaseTest {
    function testVaultOwner() public {
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
        address vaultOwner = Ownable(address(govNFT.idToVault(tokenId))).owner();
        assertEq(vaultOwner, address(govNFT));
    }

    function testWithdraw() public {
        Vault vault = new Vault(testToken);

        assertEq(IERC20(testToken).balanceOf(address(vault)), 0);
        assertEq(IERC20(testToken).balanceOf(address(admin)), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(address(this)), 0);

        admin.transfer(testToken, address(vault), TOKEN_100K);
        vault.withdraw(address(this), 5 * TOKEN_10K);

        assertEq(IERC20(testToken).balanceOf(address(vault)), 5 * TOKEN_10K);
        assertEq(IERC20(testToken).balanceOf(address(admin)), 0);
        assertEq(IERC20(testToken).balanceOf(address(this)), 5 * TOKEN_10K);

        address testAddr = makeAddr("alice");
        vault.withdraw(testAddr, 5 * TOKEN_10K);

        assertEq(IERC20(testToken).balanceOf(address(vault)), 0);
        assertEq(IERC20(testToken).balanceOf(address(admin)), 0);
        assertEq(IERC20(testToken).balanceOf(address(this)), 5 * TOKEN_10K);
        assertEq(IERC20(testToken).balanceOf(testAddr), 5 * TOKEN_10K);
    }

    function testCannotWithdrawIfNotAdmin() public {
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
        IVault vault = govNFT.idToVault(tokenId);

        assertEq(IERC20(testToken).balanceOf(address(vault)), TOKEN_100K);

        address testAddr = makeAddr("alice");

        vm.prank(testAddr);
        vm.expectRevert();
        vault.withdraw(testAddr, TOKEN_100K);

        assertEq(IERC20(testToken).balanceOf(address(vault)), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(testAddr), 0);

        vm.prank(address(govNFT));
        vault.withdraw(testAddr, TOKEN_100K);

        assertEq(IERC20(testToken).balanceOf(address(vault)), 0);
        assertEq(IERC20(testToken).balanceOf(testAddr), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(address(admin)), 0);
    }
}