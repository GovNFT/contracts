// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";
import "test/utils/MockAirdropper.sol";

contract SplitFullTest is BaseTest {
    uint256 tokenId;
    uint256 tokenId2;

    function _setUp() public override {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        tokenId = govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_100K,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 2,
            _cliffLength: WEEK,
            _description: ""
        });
        admin.approve(testGovernanceToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        tokenId2 = govNFT.createLock({
            _token: testGovernanceToken,
            _recipient: address(recipient),
            _amount: TOKEN_100K,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 2,
            _cliffLength: WEEK,
            _description: ""
        });
    }

    function test_Split() public {
        IGovNFT.Lock memory lock = govNFT.locks(tokenId);
        address oldVault = lock.vault;
        uint256 oldVaultBalance = IERC20(testToken).balanceOf(oldVault);
        assertEq(lock.totalLocked, TOKEN_100K);
        assertEq(lock.totalClaimed, 0);
        assertEq(IVault(oldVault).owner(), address(govNFT));

        vm.prank(address(recipient));
        vm.expectEmit(true, true, false, true, address(govNFT));
        emit IGovNFT.SplitFull({owner: address(recipient), oldVault: oldVault, newVault: address(0)});
        govNFT.split(tokenId);

        lock = govNFT.locks(tokenId);
        address newVault = lock.vault;
        uint256 newVaultBalance = IERC20(testToken).balanceOf(newVault);
        assertEq(lock.totalLocked, TOKEN_100K);
        assertEq(lock.totalClaimed, 0);
        assertEq(IERC20(testToken).balanceOf(oldVault), 0);
        assertEq(IVault(oldVault).owner(), address(recipient));
        assertEq(IVault(newVault).owner(), address(govNFT));
        assertNotEq(oldVault, newVault);
        assertEq(newVaultBalance, oldVaultBalance);
    }

    function test_SplitUpdateDelegatee() public {
        address delegatee = makeAddr("delegatee");

        address oldVault = govNFT.locks(tokenId2).vault;
        assertEq(IVotes(testGovernanceToken).delegates(oldVault), address(0));

        vm.startPrank(address(recipient));

        govNFT.delegate(tokenId2, delegatee);
        assertEq(IVotes(testGovernanceToken).delegates(oldVault), delegatee);

        govNFT.split(tokenId2);

        address newVault = govNFT.locks(tokenId2).vault;

        assertEq(IVotes(testGovernanceToken).delegates(oldVault), delegatee);
        assertEq(IVotes(testGovernanceToken).delegates(newVault), delegatee);
    }

    function test_SplitAndClaimAirdrop() public {
        IGovNFT.Lock memory lock = govNFT.locks(tokenId);
        address oldVault = lock.vault;

        MockAirdropper mockAirdropper = new MockAirdropper({
            _airdropToken: airdropToken,
            _airdropAmount: TOKEN_10K,
            _airdropReceiver: oldVault
        });
        deal(airdropToken, address(mockAirdropper), TOKEN_10K);

        vm.prank(address(recipient));
        govNFT.split(tokenId);

        lock = govNFT.locks(tokenId);
        address newVault = lock.vault;

        assertEq(IERC20(airdropToken).balanceOf(address(recipient)), 0);
        assertEq(IERC20(airdropToken).balanceOf(oldVault), 0);
        assertEq(IERC20(airdropToken).balanceOf(newVault), 0);

        vm.prank(address(recipient));
        vm.expectRevert(MockAirdropper.OnlyAirdropReceiver.selector);
        mockAirdropper.claimAirdrop();

        bytes memory data = abi.encodeWithSelector(MockAirdropper.claimAirdrop.selector);

        vm.prank(address(govNFT));
        vm.expectRevert(abi.encodeWithSelector(IVault.NotOwner.selector, address(govNFT)));
        IVault(oldVault).execute(address(mockAirdropper), data);

        vm.prank(address(recipient));
        emit MockAirdropper.ClaimedAirdrop(oldVault);
        IVault(oldVault).execute(address(mockAirdropper), data);

        assertEq(IERC20(airdropToken).balanceOf(address(recipient)), 0);
        assertEq(IERC20(airdropToken).balanceOf(oldVault), TOKEN_10K);

        vm.prank(address(recipient));
        IVault(oldVault).sweep(airdropToken, address(recipient), TOKEN_10K);

        assertEq(IERC20(airdropToken).balanceOf(address(recipient)), TOKEN_10K);
        assertEq(IERC20(airdropToken).balanceOf(oldVault), 0);
    }
}
