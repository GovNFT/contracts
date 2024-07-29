// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract VaultTest is BaseTest {
    function test_VaultOwner() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_100K,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 2,
            _cliffLength: WEEK,
            _description: ""
        });

        IGovNFT.Lock memory lock = govNFT.locks(tokenId);

        address vaultOwner = IVault(lock.vault).owner();
        assertEq(vaultOwner, address(govNFT));
    }

    function test_Withdraw() public {
        Vault vault = new Vault();
        vault.initialize(testToken);

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

    function test_RevertIf_WithdrawIfNotAdmin() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_100K,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 2,
            _cliffLength: WEEK,
            _description: ""
        });
        IGovNFT.Lock memory lock = govNFT.locks(tokenId);

        assertEq(IERC20(testToken).balanceOf(lock.vault), TOKEN_100K);

        address testAddr = makeAddr("alice");

        vm.prank(testAddr);
        vm.expectRevert();
        IVault(lock.vault).withdraw(testAddr, TOKEN_100K);

        assertEq(IERC20(testToken).balanceOf(lock.vault), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(testAddr), 0);

        vm.prank(address(govNFT));
        IVault(lock.vault).withdraw(testAddr, TOKEN_100K);

        assertEq(IERC20(testToken).balanceOf(lock.vault), 0);
        assertEq(IERC20(testToken).balanceOf(testAddr), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(address(admin)), 0);
    }

    function test_Sweep() public {
        Vault vault = new Vault();
        vault.initialize(testToken);

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

    function test_RevertIf_SweepIfNotAdmin() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_100K,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 2,
            _cliffLength: WEEK,
            _description: ""
        });
        IGovNFT.Lock memory lock = govNFT.locks(tokenId);
        IVault vault = IVault(lock.vault);

        assertEq(IERC20(testToken).balanceOf(lock.vault), TOKEN_100K);

        address testAddr = makeAddr("alice");

        vm.prank(testAddr);
        vm.expectRevert();
        vault.sweep(testToken, testAddr, TOKEN_100K);

        assertEq(IERC20(testToken).balanceOf(lock.vault), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(testAddr), 0);

        vm.prank(address(govNFT));
        vault.sweep(testToken, testAddr, TOKEN_100K);

        assertEq(IERC20(testToken).balanceOf(lock.vault), 0);
        assertEq(IERC20(testToken).balanceOf(testAddr), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(address(admin)), 0);
    }
}
