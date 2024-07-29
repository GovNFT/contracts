// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract DelegateUnitConcreteTest is BaseTest {
    Vault public vault;
    address public testAddr;

    function _setUp() public override {
        vault = new Vault();
        testAddr = makeAddr("alice");

        vm.prank(address(admin));
        vault.initialize(testGovernanceToken);
    }

    function test_WhenCallerIsNotOwner() external {
        // It should revert with NotOwner
        vm.expectRevert(abi.encodeWithSelector(IVault.NotOwner.selector, address(this)));
        vault.delegate({_delegatee: testAddr});
    }

    function test_WhenCallerIsOwner() external {
        // It should delegate to delegatee
        // It should emit {DelegateChanged} event
        vm.startPrank(address(admin));
        vm.expectEmit(address(testGovernanceToken));
        emit IVotes.DelegateChanged({delegator: address(vault), fromDelegate: address(0), toDelegate: testAddr});
        vault.delegate({_delegatee: testAddr});
    }
}
