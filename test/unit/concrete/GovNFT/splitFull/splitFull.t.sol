// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract SplitFullUnitConcreteTest is BaseTest {
    uint256 tokenId;

    function _setUp() public override {
        admin.approve(testGovernanceToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        tokenId = govNFT.createLock({
            _token: testGovernanceToken,
            _recipient: address(recipient),
            _amount: TOKEN_100K,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 2,
            _cliffLength: WEEK,
            _description: ""
        });
    }

    function test_WhenCallerIsNotAuthorized() external {
        // It should revert with OwnableUnauthorizedAccount
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(this), tokenId)
        );
        govNFT.split(tokenId);
    }

    modifier whenCallerIsAuthorized() {
        vm.startPrank(address(recipient));
        _;
    }

    function test_GivenVaultBalanceAfterTransferIsSmallerThanAmount() external whenCallerIsAuthorized {
        address token = address(new MockFeeERC20("TEST", "TEST", 18));
        MockFeeERC20(token).setFeeWhitelist(address(govNFT), true);
        deal(token, address(admin), TOKEN_100K);
        admin.approve(token, address(govNFT), TOKEN_100K);
        vm.startPrank(address(admin));
        tokenId = govNFT.createLock({
            _token: token,
            _recipient: address(recipient),
            _amount: TOKEN_100K,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 2,
            _cliffLength: WEEK,
            _description: ""
        });

        vm.startPrank(address(recipient));
        // It should revert with InsufficientAmount
        vm.expectRevert(IGovNFT.InsufficientAmount.selector);
        govNFT.split(tokenId);
    }

    function test_GivenVaultBalanceIsEqualOrGreaterThanAmount() external whenCallerIsAuthorized {
        IGovNFT.Lock memory lockBefore = govNFT.locks(tokenId);
        uint256 oldVaultBalance = IERC20(testGovernanceToken).balanceOf(lockBefore.vault);
        IVault oldVault = IVault(lockBefore.vault);
        address delegatee = makeAddr("delegatee");
        govNFT.delegate(tokenId, delegatee);
        assertEq(IVotes(testGovernanceToken).delegates(lockBefore.vault), delegatee);

        // It should emit a {SplitFull} event
        vm.expectEmit(true, true, false, true, address(govNFT));
        emit IGovNFT.SplitFull({owner: address(recipient), oldVault: lockBefore.vault, newVault: address(0)});
        govNFT.split(tokenId);

        IGovNFT.Lock memory lockAfter = govNFT.locks(tokenId);
        IVault newVault = IVault(lockAfter.vault);
        // It should create a new vault
        // It should set new vault as lock's vault
        assertNotEq(address(oldVault), address(newVault));
        // It should send all lock token balance to new vault
        assertEq(IERC20(testGovernanceToken).balanceOf(address(oldVault)), 0);
        assertEq(IERC20(testGovernanceToken).balanceOf(address(newVault)), oldVaultBalance);
        // It should set same delegatee
        assertEq(
            IVotes(testGovernanceToken).delegates(address(oldVault)),
            IVotes(testGovernanceToken).delegates(address(newVault))
        );

        // It should transfer ownership of old vault
        assertEq(oldVault.owner(), address(recipient));
        assertEq(newVault.owner(), address(govNFT));

        assertEq(oldVault.token(), newVault.token());
    }
}
