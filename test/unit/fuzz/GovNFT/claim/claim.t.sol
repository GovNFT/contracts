// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract ClaimUnitFuzzTest is BaseTest {
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
            _cliffLength: 0,
            _description: ""
        });
    }

    modifier whenCallerIsAuthorized() {
        vm.startPrank(address(recipient));
        _;
        vm.stopPrank();
    }

    modifier whenBeneficiaryIsNotAddressZero() {
        beneficiary = makeAddr("alice");
        _;
    }

    modifier givenClaimableIsNotZero(
        uint40 time,
        uint40 min,
        uint40 max
    ) {
        time = uint40(bound(time, min, max));
        skip(time); // skip to unlock claimable
        assertGt(govNFT.unclaimed(tokenId), 0);
        _;
    }

    function testFuzz_GivenUnclaimedBeforeSplitIsZero(
        uint40 time,
        uint256 amountToClaim
    )
        external
        whenCallerIsAuthorized
        whenBeneficiaryIsNotAddressZero
        givenClaimableIsNotZero(time, 1, type(uint40).max)
    {
        amountToClaim = bound(amountToClaim, 1, type(uint256).max);
        IGovNFT.Lock memory lock = govNFT.locks(tokenId);
        IERC20 token = IERC20(lock.token);
        uint256 claimable = Math.min(govNFT.unclaimed(tokenId), amountToClaim);
        uint256 vaultBalance = token.balanceOf(lock.vault);

        assertEq(lock.unclaimedBeforeSplit, 0);

        // It should emit a {Claim} event
        vm.expectEmit(address(govNFT));
        emit IGovNFT.Claim({tokenId: tokenId, recipient: beneficiary, claimed: claimable});
        govNFT.claim({_tokenId: tokenId, _beneficiary: beneficiary, _amount: amountToClaim});

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
            amount: (TOKEN_100K - govNFT.unclaimed(tokenId)) / 2,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: 0,
            description: ""
        });
        govNFT.split(tokenId, paramsList);

        lock = govNFT.locks(tokenId);

        assertGt(lock.unclaimedBeforeSplit, 0);
        _;
    }

    function testFuzz_GivenUnclaimedBeforeSplitIsSmallerThanClaimable(
        uint40 timeBeforeSplit,
        uint40 timeAfterSplit,
        uint256 amountToClaim
    )
        external
        whenCallerIsAuthorized
        whenBeneficiaryIsNotAddressZero
        givenClaimableIsNotZero(timeBeforeSplit, 1, (govNFT.locks(tokenId).end - uint40(block.timestamp) - 1))
        givenUnclaimedBeforeSplitIsGreaterThanZero
    {
        //make claimable > unclaimedBeforeSplit by vesting some tokens
        skip(bound(timeAfterSplit, 1, type(uint256).max));

        amountToClaim = bound(amountToClaim, 1, type(uint256).max);

        IGovNFT.Lock memory lock = govNFT.locks(tokenId);
        IERC20 token = IERC20(lock.token);
        uint256 claimable = Math.min(govNFT.unclaimed(tokenId), amountToClaim);
        uint256 vaultBalance = token.balanceOf(lock.vault);
        uint256 unclaimedBeforeSplitBefore = lock.unclaimedBeforeSplit;
        uint256 totalUnclaimed = govNFT.unclaimed(tokenId);

        assertGt(totalUnclaimed, lock.unclaimedBeforeSplit);

        // It should emit a {Claim} event
        vm.expectEmit(address(govNFT));
        emit IGovNFT.Claim({tokenId: tokenId, recipient: beneficiary, claimed: claimable});
        govNFT.claim({_tokenId: tokenId, _beneficiary: beneficiary, _amount: amountToClaim});

        lock = govNFT.locks(tokenId);
        // If amountToClaim >= unclaimedBeforeSplit, it should increase `totalClaimed` by `claimable - unclaimedBeforeSplit`
        assertEq(
            lock.totalClaimed,
            claimable > unclaimedBeforeSplitBefore ? claimable - unclaimedBeforeSplitBefore : lock.totalClaimed
        );

        // It should withdraw funds from vault and send to beneficiary
        assertEq(token.balanceOf(beneficiary), claimable);
        assertEq(token.balanceOf(lock.vault), vaultBalance - claimable);

        // It should decrease `unclaimedBeforeSplit` by amountToClaim (until 0)
        assertEq(
            lock.unclaimedBeforeSplit,
            amountToClaim > unclaimedBeforeSplitBefore ? 0 : unclaimedBeforeSplitBefore - amountToClaim
        );
    }

    function testFuzz_GivenUnclaimedBeforeSplitIsEqualOrGreaterThanClaimable(
        uint40 time
    )
        external
        whenCallerIsAuthorized
        whenBeneficiaryIsNotAddressZero
        givenClaimableIsNotZero(time, 1, govNFT.locks(tokenId).end - uint40(block.timestamp) - 1)
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

    function testFuzz_ClaimPartial(uint40 timeskip) public {
        uint40 _start = uint40(block.timestamp);
        uint40 _end = _start + WEEK * 6;
        timeskip = uint40(bound(timeskip, 0, _end - _start));
        deal(testToken, address(admin), TOKEN_100K);
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        tokenId = govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_100K,
            _startTime: _start,
            _endTime: _end,
            _cliffLength: 0,
            _description: ""
        });

        IGovNFT.Lock memory lock = govNFT.locks(tokenId);

        skip(timeskip);

        vm.prank(address(recipient));
        govNFT.claim({_tokenId: tokenId, _beneficiary: address(recipient), _amount: lock.totalLocked}); // claims available tokens
        uint256 expectedAmount = Math.min(
            (lock.totalLocked * (uint40(block.timestamp) - lock.start)) / (lock.end - lock.start),
            lock.totalLocked
        );

        lock = govNFT.locks(tokenId);
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked - expectedAmount);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), expectedAmount);
        assertEq(lock.totalClaimed, expectedAmount);
        assertEq(govNFT.unclaimed(tokenId), 0);
    }

    function testFuzz_MultipleClaims(uint8 _cycles) public {
        vm.assume(_cycles > 0);
        deal(testToken, address(admin), TOKEN_100K);
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        tokenId = govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_100K,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 2,
            _cliffLength: 0,
            _description: ""
        });
        IGovNFT.Lock memory lock = govNFT.locks(tokenId);
        IERC20 token = IERC20(testToken);

        uint256 duration = lock.end - lock.start;
        uint256 cycles = uint256(_cycles);

        uint256 govBalance = token.balanceOf(lock.vault);
        uint256 balance = 0;

        uint256 timeskip = duration / cycles;
        vm.startPrank(address(recipient));
        for (uint256 i = 0; i < cycles; i++) {
            if (i == 0) {
                skip(timeskip + (duration % cycles));
            }
            // remove any dust on first iteration
            else {
                skip(timeskip);
            }

            lock = govNFT.locks(tokenId);
            govNFT.claim({_tokenId: tokenId, _beneficiary: address(recipient), _amount: lock.totalLocked}); // claims available tokens
            uint256 expectedAmount = ((lock.totalLocked * (uint40(block.timestamp) - lock.start)) /
                (lock.end - lock.start)) - lock.totalClaimed;

            // assert balance transferred from govnft
            uint256 newBalance = token.balanceOf(lock.vault);
            assertEq(newBalance, govBalance - expectedAmount);
            govBalance = newBalance;

            // assert balance received from recipient
            newBalance = token.balanceOf(address(recipient));
            assertEq(newBalance, balance + expectedAmount);
            balance = newBalance;
        }
        vm.stopPrank();
        assertEq(token.balanceOf(address(recipient)), lock.totalLocked);
        assertEq(token.balanceOf(lock.vault), 0);
        assertEq(token.balanceOf(address(govNFT)), 0);
    }
}
