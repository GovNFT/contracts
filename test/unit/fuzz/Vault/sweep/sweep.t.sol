// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract SweepUnitFuzzTest is BaseTest {
    Vault public vault;

    function _setUp() public override {
        vault = new Vault();
        vm.prank(address(admin));
        vault.initialize(testToken);
    }

    function testFuzz_WhenCallerIsNotOwner(address caller) external {
        vm.assume(caller != address(admin) && caller != address(0));
        // It should revert with NotOwner
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(IVault.NotOwner.selector, caller));
        vault.sweep({_token: testToken, _recipient: address(admin), _amount: 0});
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(address(admin));
        _;
    }

    function testFuzz_WhenAmountToSweepIsLargerThanVaultBalance(
        uint256 airdropAmount,
        uint256 sweepAmount
    ) external whenCallerIsOwner {
        airdropAmount = bound(airdropAmount, 0, MAX_TOKENS - 1);
        sweepAmount = bound(sweepAmount, airdropAmount + 1, type(uint256).max);

        // airdrop lock tokens to vault
        deal(testToken, address(admin), airdropAmount);
        admin.transfer(testToken, address(vault), airdropAmount);

        // It should revert with ERC20InsufficientBalance
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(vault),
                airdropAmount,
                sweepAmount
            )
        );
        vault.sweep({_token: testToken, _recipient: address(admin), _amount: sweepAmount});
    }

    function testFuzz_WhenAmountToSweepIsEqualOrSmallerThanVaultBalance(
        uint256 airdropAmount,
        uint256 sweepAmount
    ) external whenCallerIsOwner {
        airdropAmount = bound(airdropAmount, 0, MAX_TOKENS);
        sweepAmount = bound(sweepAmount, 0, airdropAmount);

        // airdrop lock tokens to vault
        deal(testToken, address(admin), airdropAmount);
        admin.transfer(testToken, address(vault), airdropAmount);

        // It should sweep to recipient
        assertEq(IERC20(testToken).balanceOf(address(admin)), 0);
        assertEq(IERC20(testToken).balanceOf(address(vault)), airdropAmount);

        vault.sweep({_token: testToken, _recipient: address(admin), _amount: sweepAmount});

        assertEq(IERC20(testToken).balanceOf(address(admin)), sweepAmount);
        assertEq(IERC20(testToken).balanceOf(address(vault)), airdropAmount - sweepAmount);
    }
}
