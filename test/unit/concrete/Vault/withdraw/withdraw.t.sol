// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract WithdrawUnitConcreteTest is BaseTest {
    IVault public vault;

    function _setUp() public override {
        vault = new Vault();
        vm.prank(address(admin));
        vault.initialize(testToken);
        deal(testToken, address(vault), TOKEN_100K);
    }

    function test_WhenCallerIsNotOwner() external {
        // It should revert with NotOwner
        vm.expectRevert(abi.encodeWithSelector(IVault.NotOwner.selector, address(this)));
        vault.withdraw({_recipient: address(this), _amount: TOKEN_100K});
    }

    function test_WhenCallerIsOwner() external {
        assertEq(IERC20(testToken).balanceOf(address(vault)), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        vm.prank(address(admin));
        vault.withdraw({_recipient: address(recipient), _amount: TOKEN_100K});

        // It should transfer to recipient
        assertEq(IERC20(testToken).balanceOf(address(vault)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), TOKEN_100K);
    }
}
