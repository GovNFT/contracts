// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract SetOwnerUnitConcreteTest is BaseTest {
    Vault public vault;
    address public owner;

    function _setUp() public override {
        vault = new Vault();
        vm.prank(address(admin));
        vault.initialize(testToken);
    }

    function test_WhenCallerIsNotOwner() external {
        // It should revert with NotOwner
        vm.expectRevert(abi.encodeWithSelector(IVault.NotOwner.selector, address(this)));
        vault.setOwner({_newOwner: owner});
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(address(admin));
        assertEq(address(admin), vault.owner());
        _;
    }

    function test_WhenNewOwnerIsAddressZero() external whenCallerIsOwner {
        assertEq(owner, address(0));
        // It should revert with ZeroAddress
        vm.expectRevert(IVault.ZeroAddress.selector);
        vault.setOwner({_newOwner: owner});
    }

    function test_WhenNewOwnerIsNotAddressZero() external whenCallerIsOwner {
        owner = address(recipient);
        // It should set owner to new owner
        vault.setOwner({_newOwner: owner});
        assertEq(vault.owner(), owner);
    }
}
