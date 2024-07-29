// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract WithdrawUnitWithdrawTest is BaseTest {
    IVault public vault;

    function _setUp() public override {
        vault = new Vault();
        vm.prank(address(admin));
        vault.initialize(testToken);
    }

    function testFuzz_WhenCallerIsNotOwner(address caller) external {
        vm.assume(caller != address(admin) && caller != address(0));
        vm.prank(caller);
        // It should revert with NotOwner
        vm.expectRevert(abi.encodeWithSelector(IVault.NotOwner.selector, caller));
        vault.withdraw({_recipient: caller, _amount: TOKEN_100K});
    }

    function testFuzz_WhenCallerIsOwner(address beneficiary, uint256 initialBal, uint256 amount) external {
        vm.assume(beneficiary != address(0) && beneficiary != address(vault));

        initialBal = bound(amount, 1, type(uint256).max);
        amount = bound(amount, 1, initialBal);
        deal(testToken, address(vault), initialBal);
        deal(testToken, beneficiary, 0); // reset beneficiary balance

        assertEq(IERC20(testToken).balanceOf(address(vault)), initialBal);
        assertEq(IERC20(testToken).balanceOf(beneficiary), 0);

        vm.prank(address(admin));
        vault.withdraw({_recipient: beneficiary, _amount: amount});

        // It should transfer to recipient
        assertEq(IERC20(testToken).balanceOf(address(vault)), initialBal - amount);
        assertEq(IERC20(testToken).balanceOf(beneficiary), amount);
    }
}
