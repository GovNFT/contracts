// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract SweepTest is BaseTest {
    uint256 public tokenId;
    address public vault;

    function _setUp() public override {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        tokenId = govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            uint40(block.timestamp),
            uint40(block.timestamp) + WEEK * 2,
            WEEK
        );

        vault = govNFT.locks(tokenId).vault;

        //airdrop 100K tokens to the govNFT's vault
        airdropper.transfer(airdropToken, vault, TOKEN_100K);
    }

    function _checkClaimsAfterSweeps(uint256 from, uint256 splitToken, uint256 amount) internal {
        // check claims on parent token
        IGovNFT.Lock memory lock = govNFT.locks(from);
        vm.warp(lock.end); // warp to end of vesting period

        // sweep does not allow to claim any vested tokens
        vm.startPrank(address(recipient));
        vm.expectRevert(IGovNFT.ZeroAmount.selector);
        govNFT.sweep(from, testToken, address(recipient));

        // all tokens have finished vesting
        uint256 vaultBal = IERC20(testToken).balanceOf(lock.vault);
        assertEq(vaultBal, lock.initialDeposit - amount);
        assertEq(govNFT.unclaimed(from), vaultBal);

        uint256 oldBal = IERC20(testToken).balanceOf(address(recipient));
        assertEq(oldBal, TOKEN_100K);

        // vested tokens can be claimed as expected
        govNFT.claim(from, address(recipient), type(uint256).max);
        assertEq(IERC20(testToken).balanceOf(lock.vault), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), oldBal + (lock.initialDeposit - amount));

        // check claims on split token
        IGovNFT.Lock memory splitLock = govNFT.locks(splitToken);

        // sweep does not allow to claim any vested tokens
        vm.startPrank(address(recipient2));
        vm.expectRevert(IGovNFT.ZeroAmount.selector);
        govNFT.sweep(splitToken, testToken, address(recipient2));

        // all tokens have finished vesting
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(splitLock.vault), amount);
        assertEq(govNFT.unclaimed(splitToken), amount);
        assertEq(splitLock.totalLocked, amount);

        // vested tokens can be claimed as expected
        govNFT.claim(splitToken, address(recipient2), type(uint256).max);
        assertEq(IERC20(testToken).balanceOf(splitLock.vault), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), amount);

        assertEq(govNFT.unclaimed(splitToken), 0);
        assertEq(govNFT.unclaimed(from), 0);
    }

    function test_SweepFull() public {
        assertEq(IERC20(airdropToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(airdropToken).balanceOf(vault), TOKEN_100K);
        assertEq(IERC20(airdropToken).balanceOf(address(admin)), 0);
        assertEq(IERC20(airdropToken).balanceOf(address(recipient)), 0);

        vm.prank(address(recipient));
        vm.expectEmit(true, true, true, true, address(govNFT));
        emit IGovNFT.Sweep({tokenId: tokenId, token: airdropToken, receiver: address(recipient), amount: TOKEN_100K});
        govNFT.sweep(tokenId, airdropToken, address(recipient));

        assertEq(IERC20(airdropToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(airdropToken).balanceOf(vault), 0);
        assertEq(IERC20(airdropToken).balanceOf(address(admin)), 0);
        assertEq(IERC20(airdropToken).balanceOf(address(recipient)), TOKEN_100K);
    }

    function test_SweepFullAirdropTokenSameAsLockToken() public {
        //airdrop 100k tokens (as airdrop) to the govNFT's vault
        airdropper.transfer(testToken, vault, TOKEN_100K);

        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(vault), 2 * TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(address(admin)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        vm.prank(address(recipient));
        vm.expectEmit(true, true, true, true, address(govNFT));
        emit IGovNFT.Sweep({tokenId: tokenId, token: testToken, receiver: address(recipient), amount: TOKEN_100K});
        govNFT.sweep(tokenId, testToken, address(recipient), TOKEN_100K);

        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(vault), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(address(admin)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), TOKEN_100K);
    }

    function test_SweepToDifferentRecipient() public {
        address testUser = address(0x123);
        assertEq(IERC20(airdropToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(airdropToken).balanceOf(vault), TOKEN_100K);
        assertEq(IERC20(airdropToken).balanceOf(address(admin)), 0);
        assertEq(IERC20(airdropToken).balanceOf(address(recipient)), 0);
        assertEq(IERC20(airdropToken).balanceOf(testUser), 0);

        vm.prank(address(recipient));
        vm.expectEmit(true, true, true, true, address(govNFT));
        emit IGovNFT.Sweep({tokenId: tokenId, token: airdropToken, receiver: testUser, amount: TOKEN_100K});
        govNFT.sweep(tokenId, airdropToken, testUser);

        assertEq(IERC20(airdropToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(airdropToken).balanceOf(vault), 0);
        assertEq(IERC20(airdropToken).balanceOf(address(admin)), 0);
        assertEq(IERC20(airdropToken).balanceOf(address(recipient)), 0);
        assertEq(IERC20(airdropToken).balanceOf(testUser), TOKEN_100K);
    }

    function testFuzz_SweepPartial(uint256 amount) public {
        amount = bound(amount, 1, TOKEN_100K);
        uint256 amountLeftToSweep = TOKEN_100K;

        uint256 amountSwept;
        uint256 cycles; //prevent long running tests
        while (amountLeftToSweep > 0 && cycles < 100) {
            if (amount > amountLeftToSweep) amount = amountLeftToSweep;
            amountSwept += amount;

            vm.prank(address(recipient));
            vm.expectEmit(true, true, true, true, address(govNFT));
            emit IGovNFT.Sweep({tokenId: tokenId, token: airdropToken, receiver: address(recipient), amount: amount});
            govNFT.sweep(tokenId, airdropToken, address(recipient), amount);

            assertEq(IERC20(airdropToken).balanceOf(address(recipient)), amountSwept);
            assertEq(IERC20(airdropToken).balanceOf(vault), TOKEN_100K - amountSwept);

            amountLeftToSweep -= amount;
            cycles++;
        }
        assertEq(IERC20(airdropToken).balanceOf(address(recipient)), amountSwept);
        assertEq(IERC20(airdropToken).balanceOf(vault), TOKEN_100K - amountSwept);
    }

    function testFuzz_MultipleFullSweepsDontAffectGrantWhenAirdropTokenSameAsGrant(
        uint32 _timeskip,
        uint8 cycles
    ) public {
        uint256 _start = uint40(block.timestamp);
        uint256 _end = _start + WEEK * 6;
        uint256 timeskip = uint256(_timeskip);
        timeskip = bound(timeskip, 0, _end - _start);

        IGovNFT.Lock memory lock = govNFT.locks(tokenId);

        uint256 expectedClaim;
        uint256 balanceRecipient;
        skip(lock.cliffLength);
        for (uint256 i = 0; i <= cycles; i++) {
            deal(testToken, address(airdropper), TOKEN_100K);
            //airdrop amount
            airdropper.transfer(testToken, vault, TOKEN_100K);
            skip(timeskip);
            expectedClaim = Math.min(
                (lock.totalLocked * (uint40(block.timestamp) - lock.start)) / (lock.end - lock.start),
                lock.totalLocked
            );

            //full sweep
            vm.prank(address(recipient));
            govNFT.sweep(tokenId, testToken, address(recipient));
            balanceRecipient += TOKEN_100K;

            vm.prank(address(recipient));
            govNFT.claim(tokenId, address(recipient), lock.totalLocked);

            assertEq(IERC20(testToken).balanceOf(vault), lock.totalLocked - expectedClaim);
            assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
            assertEq(IERC20(testToken).balanceOf(address(recipient)), balanceRecipient + expectedClaim);

            lock = govNFT.locks(tokenId);
            assertEq(lock.totalClaimed, expectedClaim);
            assertEq(govNFT.unclaimed(tokenId), 0);
        }
    }

    function testFuzz_PartialSweepDoesntAffectGrantWhenAirdropTokenSameAsGrant(
        uint32 _timeskip,
        uint256 amount
    ) public {
        amount = bound(amount, 1, TOKEN_100K);
        //airdrop amount
        airdropper.transfer(testToken, vault, TOKEN_100K);
        uint256 _start = uint40(block.timestamp);
        uint256 _end = _start + WEEK * 6;
        uint256 timeskip = uint256(_timeskip);
        timeskip = bound(timeskip, 0, _end - _start);

        IGovNFT.Lock memory lock = govNFT.locks(tokenId);

        skip(timeskip + lock.cliffLength);
        uint256 expectedClaim = Math.min(
            (lock.totalLocked * (uint40(block.timestamp) - lock.start)) / (lock.end - lock.start),
            lock.totalLocked
        );

        vm.prank(address(recipient));
        govNFT.sweep(tokenId, testToken, address(recipient), amount);

        assertEq(IERC20(testToken).balanceOf(vault), lock.totalLocked + TOKEN_100K - amount);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), amount);
        lock = govNFT.locks(tokenId);
        assertEq(lock.totalClaimed, 0);
        assertEq(govNFT.unclaimed(tokenId), expectedClaim);

        //check user can stil claim lock
        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient), lock.totalLocked);

        assertEq(IERC20(testToken).balanceOf(vault), lock.totalLocked + TOKEN_100K - expectedClaim - amount);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), amount + expectedClaim);
        lock = govNFT.locks(tokenId);
        assertEq(lock.totalClaimed, expectedClaim);
        assertEq(govNFT.unclaimed(tokenId), 0);
    }

    function test_SweepAfterClaim() public {
        airdropper.transfer(testToken, vault, TOKEN_100K);
        IGovNFT.Lock memory lock = govNFT.locks(tokenId);

        skip(WEEK * 2); //skip to the vesting end timestamp

        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient), lock.totalLocked);

        assertEq(IERC20(testToken).balanceOf(vault), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), TOKEN_100K);
        lock = govNFT.locks(tokenId);
        assertEq(lock.totalClaimed, lock.totalLocked);
        assertEq(govNFT.unclaimed(tokenId), 0);

        vm.prank(address(recipient));
        govNFT.sweep(tokenId, testToken, address(recipient));

        assertEq(IERC20(testToken).balanceOf(vault), 0);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 2 * TOKEN_100K);
        lock = govNFT.locks(tokenId);
        assertEq(lock.totalClaimed, lock.totalLocked);
        assertEq(govNFT.unclaimed(tokenId), 0);
    }

    function test_SweepAfterSplit() public {
        airdropper.transfer(testToken, vault, TOKEN_100K);
        IGovNFT.Lock memory lock = govNFT.locks(tokenId);

        skip(WEEK / 2); // skip without leaving cliff

        uint256 amount = TOKEN_10K * 3;
        vm.startPrank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: WEEK / 2
        });
        uint256 splitToken = govNFT.split(tokenId, paramsList)[0];

        // Can only sweep airdropped amount on Parent Token
        assertEq(IERC20(testToken).balanceOf(vault), TOKEN_100K + (lock.totalLocked - amount));
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);

        govNFT.sweep(tokenId, testToken, address(recipient));

        assertEq(IERC20(testToken).balanceOf(vault), lock.totalLocked - amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);

        // Nothing to sweep on Split Token
        address splitVault = govNFT.locks(splitToken).vault;
        assertEq(IERC20(testToken).balanceOf(splitVault), amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);

        vm.startPrank(address(recipient2));
        vm.expectRevert(IGovNFT.ZeroAmount.selector);
        govNFT.sweep(splitToken, testToken, address(recipient2));

        assertEq(IERC20(testToken).balanceOf(splitVault), amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);

        // Can claim all vested tokens as expected
        _checkClaimsAfterSweeps(tokenId, splitToken, amount);
    }

    function test_SweepAfterSplitWithUnclaimedTokens() public {
        airdropper.transfer(testToken, vault, TOKEN_100K);
        IGovNFT.Lock memory lock = govNFT.locks(tokenId);

        skip(WEEK); // skip halfway through vestment

        uint256 amount = TOKEN_10K * 3;
        vm.startPrank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: uint40(block.timestamp),
            end: lock.end,
            cliff: 0
        });
        uint256 splitToken = govNFT.split(tokenId, paramsList)[0];

        // Can only sweep airdropped amount on Parent Token
        uint256 unclaimedAmount = govNFT.unclaimed(tokenId);
        uint256 totalLocked = govNFT.locks(tokenId).totalLocked;
        assertEq(IERC20(testToken).balanceOf(vault), TOKEN_100K + (totalLocked + unclaimedAmount));
        assertEq(lock.initialDeposit, totalLocked + unclaimedAmount + amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);

        govNFT.sweep(tokenId, testToken, address(recipient));

        assertEq(IERC20(testToken).balanceOf(vault), totalLocked + unclaimedAmount);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);

        // Nothing to sweep on Split Token
        address splitVault = govNFT.locks(splitToken).vault;
        assertEq(IERC20(testToken).balanceOf(splitVault), amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);

        vm.startPrank(address(recipient2));
        vm.expectRevert(IGovNFT.ZeroAmount.selector);
        govNFT.sweep(splitToken, testToken, address(recipient2));

        assertEq(IERC20(testToken).balanceOf(splitVault), amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);

        // Can claim all vested tokens as expected
        _checkClaimsAfterSweeps(tokenId, splitToken, amount);
    }

    function testFuzz_SweepAfterSplit(uint256 amount, uint40 timeskip) public {
        deal(testToken, address(admin), TOKEN_100K);
        vm.startPrank(address(admin));
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        uint256 from = govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            uint40(block.timestamp) + WEEK,
            uint40(block.timestamp) + WEEK * 4,
            WEEK
        );
        IGovNFT.Lock memory lock = govNFT.locks(from);
        timeskip = uint40(bound(timeskip, 0, lock.end - lock.start - 1));
        airdropper.transfer(testToken, lock.vault, TOKEN_100K);

        skip(timeskip);
        amount = bound(amount, 1, govNFT.locked(from) - 1);

        lock.cliffLength = lock.start + lock.cliffLength >= block.timestamp
            ? lock.start + lock.cliffLength - timeskip
            : 0;
        lock.start = uint40(lock.start < block.timestamp ? block.timestamp : lock.start);

        vm.startPrank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: amount,
            start: lock.start,
            end: lock.end,
            cliff: lock.cliffLength
        });
        uint256 splitToken = govNFT.split(from, paramsList)[0];

        // Can only sweep airdropped amount on Parent Token
        uint256 unclaimedAmount = govNFT.unclaimed(from);
        uint256 totalLocked = govNFT.locks(from).totalLocked;
        assertApproxEqAbs(IERC20(testToken).balanceOf(lock.vault), TOKEN_100K + (totalLocked + unclaimedAmount), 2);
        assertEq(lock.initialDeposit, totalLocked + unclaimedAmount + amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);

        govNFT.sweep(from, testToken, address(recipient));

        assertEq(IERC20(testToken).balanceOf(lock.vault), totalLocked + unclaimedAmount);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);

        // Nothing to sweep on Split Token
        address splitVault = govNFT.locks(splitToken).vault;
        assertEq(IERC20(testToken).balanceOf(splitVault), amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);

        vm.startPrank(address(recipient2));
        vm.expectRevert(IGovNFT.ZeroAmount.selector);
        govNFT.sweep(splitToken, testToken, address(recipient2));

        assertEq(IERC20(testToken).balanceOf(splitVault), amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);

        // Can claim all vested tokens as expected
        _checkClaimsAfterSweeps(from, splitToken, amount);
    }

    function test_RevertIf_SweepAfterSplitIfNoAirdrop() public {
        skip(WEEK); // skip halfway through vestment

        vm.startPrank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: 1,
            start: uint40(block.timestamp),
            end: govNFT.locks(tokenId).end,
            cliff: 0
        });
        uint256 tokenId2 = govNFT.split(tokenId, paramsList)[0];

        uint256 unclaimedAmount = govNFT.unclaimed(tokenId);

        vm.expectRevert(IGovNFT.ZeroAmount.selector);
        govNFT.sweep(tokenId, testToken, address(recipient));

        assertEqUint(IERC20(testToken).balanceOf(address(recipient)), 0);
        govNFT.claim(tokenId, address(recipient), type(uint256).max);
        assertEqUint(IERC20(testToken).balanceOf(address(recipient)), unclaimedAmount);

        unclaimedAmount = govNFT.unclaimed(tokenId2);

        vm.startPrank(address(recipient2));
        vm.expectRevert(IGovNFT.ZeroAmount.selector);
        govNFT.sweep(tokenId2, testToken, address(recipient2));

        assertEqUint(IERC20(testToken).balanceOf(address(recipient2)), 0);
        govNFT.claim(tokenId2, address(recipient2), type(uint256).max);
        assertEqUint(IERC20(testToken).balanceOf(address(recipient2)), unclaimedAmount);
    }

    function testFuzz_RevertIf_SweepAfterSplitIfNoAirdrop(uint256 amount, uint40 timeskip) public {
        IGovNFT.Lock memory lock = govNFT.locks(tokenId);

        timeskip = uint40(bound(timeskip, 0, lock.end - lock.start - 1));
        skip(timeskip);
        amount = bound(amount, 1, govNFT.locked(tokenId) - 1);

        lock.cliffLength = lock.start + lock.cliffLength >= block.timestamp
            ? lock.start + lock.cliffLength - timeskip
            : 0;
        lock.start = uint40(lock.start < block.timestamp ? block.timestamp : lock.start);

        vm.startPrank(address(recipient));
        IGovNFT.SplitParams[] memory paramsList = new IGovNFT.SplitParams[](1);
        paramsList[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            amount: 1,
            start: lock.start,
            end: lock.end,
            cliff: lock.cliffLength
        });
        uint256 tokenId2 = govNFT.split(tokenId, paramsList)[0];

        uint256 unclaimedAmount = govNFT.unclaimed(tokenId);

        vm.expectRevert(IGovNFT.ZeroAmount.selector);
        govNFT.sweep(tokenId, testToken, address(recipient));

        assertEqUint(IERC20(testToken).balanceOf(address(recipient)), 0);
        govNFT.claim(tokenId, address(recipient), type(uint256).max);
        assertEqUint(IERC20(testToken).balanceOf(address(recipient)), unclaimedAmount);

        unclaimedAmount = govNFT.unclaimed(tokenId2);

        vm.startPrank(address(recipient2));
        vm.expectRevert(IGovNFT.ZeroAmount.selector);
        govNFT.sweep(tokenId2, testToken, address(recipient2));

        assertEqUint(IERC20(testToken).balanceOf(address(recipient2)), 0);
        govNFT.claim(tokenId2, address(recipient), type(uint256).max);
        assertEqUint(IERC20(testToken).balanceOf(address(recipient2)), unclaimedAmount);
    }

    function test_SweepPermissions() public {
        address approvedUser = makeAddr("alice");
        assertEq(IERC20(airdropToken).balanceOf(approvedUser), 0);

        vm.prank(address(recipient));
        govNFT.approve(approvedUser, tokenId);

        // can sweep after getting approval on nft
        vm.prank(approvedUser);
        vm.expectEmit(true, true, true, true, address(govNFT));
        emit IGovNFT.Sweep({tokenId: tokenId, token: airdropToken, receiver: approvedUser, amount: TOKEN_1});
        govNFT.sweep(tokenId, airdropToken, approvedUser, TOKEN_1);
        assertEq(IERC20(airdropToken).balanceOf(approvedUser), TOKEN_1);

        address approvedForAllUser = makeAddr("bob");
        assertEq(IERC20(testToken).balanceOf(approvedForAllUser), 0);

        vm.prank(address(recipient));
        govNFT.setApprovalForAll(approvedForAllUser, true);

        // can sweep after getting approval for all nfts
        vm.prank(approvedForAllUser);
        vm.expectEmit(true, true, true, true, address(govNFT));
        emit IGovNFT.Sweep({tokenId: tokenId, token: airdropToken, receiver: approvedForAllUser, amount: TOKEN_1});
        govNFT.sweep(tokenId, airdropToken, approvedForAllUser, TOKEN_1);
        assertEq(IERC20(airdropToken).balanceOf(approvedForAllUser), TOKEN_1);
    }

    function test_RevertIf_SweepIfNotRecipientOrApproved() public {
        address testUser = address(0x123);
        vm.prank(testUser);
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, testUser, tokenId));
        govNFT.sweep(tokenId, airdropToken, address(admin));

        vm.prank(address(admin));
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(admin), tokenId)
        );
        govNFT.sweep(tokenId, airdropToken, address(admin));
    }

    function test_RevertIf_SweepLockTokenBeforeLockExpiryWhenNotAllowed() public {
        // Create GovNFT without ability to Sweep Lock's tokens
        deal(testToken, address(admin), TOKEN_100K);
        GovNFTSplit govNFTNoSweep = new GovNFTSplit({
            _owner: address(admin),
            _artProxy: address(0),
            _name: NAME,
            _symbol: SYMBOL,
            _earlySweepLockToken: false
        });
        admin.approve(testToken, address(govNFTNoSweep), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId2 = govNFTNoSweep.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            uint40(block.timestamp),
            uint40(block.timestamp) + WEEK * 2,
            WEEK
        );

        IGovNFT.Lock memory lock = govNFTNoSweep.locks(tokenId2);

        //airdrop 100k tokens (as airdrop) to the govNFT's vault
        airdropper.transfer(testToken, lock.vault, TOKEN_100K);

        // cannot sweep before lock expiry
        vm.prank(address(recipient));
        vm.expectRevert(abi.encodeWithSelector(IGovNFT.InvalidSweep.selector));
        govNFTNoSweep.sweep(tokenId2, testToken, address(admin));

        // cannot sweep before lock expiry
        vm.warp(lock.end - 1);
        vm.prank(address(recipient));
        vm.expectRevert(abi.encodeWithSelector(IGovNFT.InvalidSweep.selector));
        govNFTNoSweep.sweep(tokenId2, testToken, address(admin));

        assertEq(IERC20(testToken).balanceOf(lock.vault), 2 * TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(address(admin)), 0);

        // can sweep after vesting is finished
        vm.warp(lock.end);
        vm.prank(address(recipient));
        vm.expectEmit(true, true, true, true, address(govNFTNoSweep));
        emit IGovNFT.Sweep({tokenId: tokenId2, token: testToken, receiver: address(admin), amount: TOKEN_100K});
        govNFTNoSweep.sweep(tokenId2, testToken, address(admin));

        assertEq(IERC20(testToken).balanceOf(lock.vault), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(address(admin)), TOKEN_100K);
    }

    function test_RevertIf_SweepNonExistentToken() public {
        tokenId = 3;
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, tokenId));
        vm.prank(address(recipient));
        govNFT.sweep(tokenId, airdropToken, address(recipient));
    }

    function test_RevertIf_SweepIfNoAirdrop() public {
        testToken = address(new MockERC20("", "", 18));
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(vault), 0);
        assertEq(IERC20(testToken).balanceOf(address(admin)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        vm.expectRevert(IGovNFT.ZeroAmount.selector);
        vm.prank(address(recipient));
        govNFT.sweep(tokenId, testToken, address(recipient));

        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(vault), 0);
        assertEq(IERC20(testToken).balanceOf(address(admin)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);
    }

    function test_RevertIf_SweepToZeroAddress() public {
        vm.expectRevert(IGovNFT.ZeroAddress.selector);
        vm.prank(address(recipient));
        govNFT.sweep(tokenId, airdropToken, address(0));
    }
}
