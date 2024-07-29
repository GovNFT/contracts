// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";
import "test/utils/MockAirdropper.sol";

contract ExecuteUnitConcreteTest is BaseTest {
    Vault public vault;
    address public mockContract;
    bytes public data;

    function _setUp() public override {
        vault = new Vault();

        vm.prank(address(admin));
        vault.initialize(testGovernanceToken);

        mockContract = address(
            new MockAirdropper({
                _airdropToken: airdropToken,
                _airdropAmount: TOKEN_10K,
                _airdropReceiver: address(vault)
            })
        );
        data = abi.encodeWithSelector(MockAirdropper.claimAirdrop.selector);
        deal(airdropToken, mockContract, TOKEN_10K);
        assertEq(IERC20(airdropToken).balanceOf(mockContract), TOKEN_10K);
    }

    function test_WhenCallerIsNotOwner() external {
        // It should revert with NotOwner
        vm.expectRevert(abi.encodeWithSelector(IVault.NotOwner.selector, address(this)));
        vault.execute({_to: mockContract, _data: data});
    }

    function test_WhenCallerIsOwner() external {
        assertEq(IERC20(airdropToken).balanceOf(address(vault)), 0);

        vm.prank(address(admin));
        // It should execute payload
        vm.expectEmit(address(mockContract));
        emit MockAirdropper.ClaimedAirdrop(address(vault));
        vault.execute({_to: mockContract, _data: data});

        assertEq(IERC20(airdropToken).balanceOf(address(vault)), TOKEN_10K);
        assertEq(IERC20(airdropToken).balanceOf(mockContract), 0);
    }
}
