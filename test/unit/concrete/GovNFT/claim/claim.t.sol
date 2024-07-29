// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract ClaimUnitConcreteTest is BaseTest {
    uint256 tokenId;
    address beneficiary;

    function _setUp() public override {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        tokenId = govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_100K,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 4,
            _cliffLength: WEEK,
            _description: ""
        });
    }

    function test_WhenCallerIsNotAuthorized() external {
        // It should revert with ERC721InsufficientApproval
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(this), tokenId)
        );
        govNFT.claim({_tokenId: tokenId, _beneficiary: address(admin), _amount: TOKEN_100K});
    }

    modifier whenCallerIsAuthorized() {
        vm.startPrank(address(recipient));
        _;
        vm.stopPrank();
    }

    function test_WhenBeneficiaryIsAddressZero() external whenCallerIsAuthorized {
        // It should revert with ZeroAddress
        vm.expectRevert(IGovNFT.ZeroAddress.selector);
        govNFT.claim({_tokenId: tokenId, _beneficiary: beneficiary, _amount: TOKEN_100K});
    }

    modifier whenBeneficiaryIsNotAddressZero() {
        beneficiary = makeAddr("alice");
        _;
    }

    function test_GivenClaimableIsZero() external whenCallerIsAuthorized whenBeneficiaryIsNotAddressZero {
        IGovNFT.Lock memory lock = govNFT.locks(tokenId);
        IERC20 token = IERC20(lock.token);
        uint256 beneficiaryBalance = token.balanceOf(beneficiary);
        uint256 vaultBalance = token.balanceOf(lock.vault);

        assertEq(govNFT.unclaimed(tokenId), 0);

        // It should early return
        govNFT.claim({_tokenId: tokenId, _beneficiary: beneficiary, _amount: type(uint256).max});
        assertEq(token.balanceOf(beneficiary), beneficiaryBalance);
        assertEq(token.balanceOf(lock.vault), vaultBalance);
    }

    modifier givenClaimableIsNotZero() {
        skip(WEEK); // skip to unlock claimable
        assertGt(govNFT.unclaimed(tokenId), 0);
        _;
    }

    function test_GivenUnclaimedBeforeSplitIsZero()
        external
        whenCallerIsAuthorized
        whenBeneficiaryIsNotAddressZero
        givenClaimableIsNotZero
    {
        IGovNFT.Lock memory lock = govNFT.locks(tokenId);
        IERC20 token = IERC20(lock.token);
        uint256 claimable = govNFT.unclaimed(tokenId);
        uint256 vaultBalance = token.balanceOf(lock.vault);

        assertEq(lock.unclaimedBeforeSplit, 0);

        // It should emit a {Claim} event
        vm.expectEmit(address(govNFT));
        emit IGovNFT.Claim({tokenId: tokenId, recipient: beneficiary, claimed: claimable});
        govNFT.claim({_tokenId: tokenId, _beneficiary: beneficiary, _amount: type(uint256).max});

        lock = govNFT.locks(tokenId);
        // It should increase `totalClaimed` by `claimable`
        assertEq(lock.totalClaimed, claimable);

        // It should withdraw funds from vault and send to beneficiary
        assertEq(token.balanceOf(beneficiary), claimable);
        assertEq(token.balanceOf(lock.vault), vaultBalance - claimable);
    }

    modifier givenUnclaimedBeforeSplitIsGreaterThanZero() {
        assertGt(govNFT.unclaimed(tokenId), 0);

        IGovNFT.Lock memory lock = govNFT.locks(tokenId);
        //split with unclaimed tokens to have unclaimedBeforeSplit > 0
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient),
            amount: TOKEN_100K / 4,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: WEEK,
            description: ""
        });
        govNFT.split(tokenId, paramsList);

        lock = govNFT.locks(tokenId);

        assertGt(lock.unclaimedBeforeSplit, 0);
        _;
    }

    function test_GivenUnclaimedBeforeSplitIsSmallerThanClaimable()
        external
        whenCallerIsAuthorized
        whenBeneficiaryIsNotAddressZero
        givenClaimableIsNotZero
        givenUnclaimedBeforeSplitIsGreaterThanZero
    {
        //make claimable > unclaimedBeforeSplit by vesting some tokens
        skip(WEEK);

        IGovNFT.Lock memory lock = govNFT.locks(tokenId);
        IERC20 token = IERC20(lock.token);
        uint256 claimable = govNFT.unclaimed(tokenId);
        uint256 vaultBalance = token.balanceOf(lock.vault);
        uint256 unclaimedBeforeSplitBefore = lock.unclaimedBeforeSplit;

        assertGt(claimable, lock.unclaimedBeforeSplit);

        // It should emit a {Claim} event
        vm.expectEmit(address(govNFT));
        emit IGovNFT.Claim({tokenId: tokenId, recipient: beneficiary, claimed: claimable});
        govNFT.claim({_tokenId: tokenId, _beneficiary: beneficiary, _amount: type(uint256).max});

        lock = govNFT.locks(tokenId);
        // It should increase `totalClaimed` by `claimable - unclaimedBeforeSplit`
        assertEq(lock.totalClaimed, claimable - unclaimedBeforeSplitBefore);

        // It should withdraw funds from vault and send to beneficiary
        assertEq(token.balanceOf(beneficiary), claimable);
        assertEq(token.balanceOf(lock.vault), vaultBalance - claimable);

        // It should set `unclaimedBeforeSplit` to 0
        assertEq(lock.unclaimedBeforeSplit, 0);
    }

    function test_GivenUnclaimedBeforeSplitIsEqualOrGreaterThanClaimable()
        external
        whenCallerIsAuthorized
        whenBeneficiaryIsNotAddressZero
        givenClaimableIsNotZero
        givenUnclaimedBeforeSplitIsGreaterThanZero
    {
        IGovNFT.Lock memory lock = govNFT.locks(tokenId);
        IERC20 token = IERC20(lock.token);
        uint256 claimable = govNFT.unclaimed(tokenId);
        uint256 unclaimedBeforeSplitBefore = lock.unclaimedBeforeSplit;
        uint256 vaultBalance = token.balanceOf(lock.vault);

        assertGe(lock.unclaimedBeforeSplit, claimable);

        // It should emit a {Claim} event
        vm.expectEmit(address(govNFT));
        emit IGovNFT.Claim({tokenId: tokenId, recipient: beneficiary, claimed: claimable});
        govNFT.claim({_tokenId: tokenId, _beneficiary: beneficiary, _amount: type(uint256).max});

        lock = govNFT.locks(tokenId);

        // It should withdraw funds from vault and send to beneficiary
        assertEq(token.balanceOf(beneficiary), claimable);
        assertEq(token.balanceOf(lock.vault), vaultBalance - claimable);

        // It should decrease `unclaimedBeforeSplit` by `claimable`
        assertEq(lock.unclaimedBeforeSplit, unclaimedBeforeSplitBefore - claimable);
    }
}
