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
            block.timestamp,
            block.timestamp + WEEK * 2,
            WEEK
        );

        vault = govNFT.locks(tokenId).vault;

        //airdrop 100K tokens to the govNFT's vault
        airdropper.transfer(airdropToken, vault, TOKEN_100K);
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

    function test_SweepFullAirdropTokenSameAsGrantToken() public {
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
        uint256 _start = block.timestamp;
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
                (lock.totalLocked * (block.timestamp - lock.start)) / (lock.end - lock.start),
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
        uint256 _start = block.timestamp;
        uint256 _end = _start + WEEK * 6;
        uint256 timeskip = uint256(_timeskip);
        timeskip = bound(timeskip, 0, _end - _start);

        IGovNFT.Lock memory lock = govNFT.locks(tokenId);

        skip(timeskip + lock.cliffLength);
        uint256 expectedClaim = Math.min(
            (lock.totalLocked * (block.timestamp - lock.start)) / (lock.end - lock.start),
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
