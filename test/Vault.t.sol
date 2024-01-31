// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import {BaseTest} from "test/utils/BaseTest.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import "src/Vault.sol";

contract VaultTest is BaseTest {
    function testVaultOwner() public {
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

        (, , , , , , , , , address vault, ) = govNFT.locks(tokenId);

        address vaultOwner = Ownable(vault).owner();
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
        uint256 tokenId = govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 2,
            WEEK
        );
        (, , , , , , , , , address vault, ) = govNFT.locks(tokenId);

        assertEq(IERC20(testToken).balanceOf(vault), TOKEN_100K);

        address testAddr = makeAddr("alice");

        vm.prank(testAddr);
        vm.expectRevert();
        IVault(vault).withdraw(testAddr, TOKEN_100K);

        assertEq(IERC20(testToken).balanceOf(vault), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(testAddr), 0);

        vm.prank(address(govNFT));
        IVault(vault).withdraw(testAddr, TOKEN_100K);

        assertEq(IERC20(testToken).balanceOf(vault), 0);
        assertEq(IERC20(testToken).balanceOf(testAddr), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(address(admin)), 0);
    }

    function testSweep() public {
        Vault vault = new Vault(testToken);

        assertEq(IERC20(testToken).balanceOf(address(vault)), 0);
        assertEq(IERC20(testToken).balanceOf(address(admin)), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(address(this)), 0);

        admin.transfer(testToken, address(vault), TOKEN_100K);
        vault.sweep(testToken, address(this), 5 * TOKEN_10K);

        assertEq(IERC20(testToken).balanceOf(address(vault)), 5 * TOKEN_10K);
        assertEq(IERC20(testToken).balanceOf(address(admin)), 0);
        assertEq(IERC20(testToken).balanceOf(address(this)), 5 * TOKEN_10K);

        address testAddr = makeAddr("alice");
        vault.sweep(testToken, testAddr, 5 * TOKEN_10K);

        assertEq(IERC20(testToken).balanceOf(address(vault)), 0);
        assertEq(IERC20(testToken).balanceOf(address(admin)), 0);
        assertEq(IERC20(testToken).balanceOf(address(this)), 5 * TOKEN_10K);
        assertEq(IERC20(testToken).balanceOf(testAddr), 5 * TOKEN_10K);
    }

    function testCannotSweepIfNotAdmin() public {
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
        (, , , , , , , , , address _vault, ) = govNFT.locks(tokenId);
        IVault vault = IVault(_vault);

        assertEq(IERC20(testToken).balanceOf(_vault), TOKEN_100K);

        address testAddr = makeAddr("alice");

        vm.prank(testAddr);
        vm.expectRevert();
        vault.sweep(testToken, testAddr, TOKEN_100K);

        assertEq(IERC20(testToken).balanceOf(_vault), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(testAddr), 0);

        vm.prank(address(govNFT));
        vault.sweep(testToken, testAddr, TOKEN_100K);

        assertEq(IERC20(testToken).balanceOf(_vault), 0);
        assertEq(IERC20(testToken).balanceOf(testAddr), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(address(admin)), 0);
    }
}
