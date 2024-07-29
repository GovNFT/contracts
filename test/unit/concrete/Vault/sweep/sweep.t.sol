// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract SweepUnitConcreteTest is BaseTest {
    Vault public vault;

    function _setUp() public override {
        vault = new Vault();
        vm.prank(address(admin));
        vault.initialize(testToken);
    }

    function test_WhenCallerIsNotOwner() external {
        // It should revert with NotOwner
        vm.expectRevert(abi.encodeWithSelector(IVault.NotOwner.selector, address(this)));
        vault.sweep({_token: testToken, _recipient: address(admin), _amount: 0});
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(address(admin));
        _;
    }

    function test_WhenAmountToSweepIsLargerThanVaultBalance() external whenCallerIsOwner {
        uint256 airdropAmount = TOKEN_100K;
        uint256 amountToSweep = TOKEN_100K + 1 wei;

        // airdrop lock tokens to vault
        admin.transfer(testToken, address(vault), airdropAmount);

        // It should revert with ERC20InsufficientBalance
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(vault),
                airdropAmount,
                amountToSweep
            )
        );
        vault.sweep({_token: testToken, _recipient: address(admin), _amount: amountToSweep});
    }

    function test_WhenAmountToSweepIsEqualOrSmallerThanVaultBalance() external whenCallerIsOwner {
        uint256 airdropAmount = TOKEN_100K;
        uint256 amountToSweep = TOKEN_10K * 5;

        // airdrop lock tokens to vault
        admin.transfer(testToken, address(vault), airdropAmount);

        // It should sweep to recipient
        assertEq(IERC20(testToken).balanceOf(address(admin)), 0);
        assertEq(IERC20(testToken).balanceOf(address(vault)), airdropAmount);

        vault.sweep({_token: testToken, _recipient: address(admin), _amount: amountToSweep});

        assertEq(IERC20(testToken).balanceOf(address(admin)), amountToSweep);
        assertEq(IERC20(testToken).balanceOf(address(vault)), airdropAmount - amountToSweep);
    }
}
