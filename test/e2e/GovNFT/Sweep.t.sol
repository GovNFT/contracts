// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract SweepTest is BaseTest {
    uint256 public tokenId;
    address public vault;

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
        govNFT.sweep({_tokenId: from, _token: testToken, _recipient: address(recipient)});

        // all tokens have finished vesting
        uint256 vaultBal = IERC20(testToken).balanceOf(lock.vault);
        assertEq(vaultBal, lock.initialDeposit - amount);
        assertEq(govNFT.unclaimed(from), vaultBal);

        uint256 oldBal = IERC20(testToken).balanceOf(address(recipient));
        assertEq(oldBal, TOKEN_100K);

        // vested tokens can be claimed as expected
        govNFT.claim({_tokenId: from, _beneficiary: address(recipient), _amount: type(uint256).max});
        assertEq(IERC20(testToken).balanceOf(lock.vault), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), oldBal + (lock.initialDeposit - amount));

        // check claims on split token
        IGovNFT.Lock memory splitLock = govNFT.locks(splitToken);

        // sweep does not allow to claim any vested tokens
        vm.startPrank(address(recipient2));
        vm.expectRevert(IGovNFT.ZeroAmount.selector);
        govNFT.sweep({_tokenId: splitToken, _token: testToken, _recipient: address(recipient2)});

        // all tokens have finished vesting
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(splitLock.vault), amount);
        assertEq(govNFT.unclaimed(splitToken), amount);
        assertEq(splitLock.totalLocked, amount);

        // vested tokens can be claimed as expected
        govNFT.claim({_tokenId: splitToken, _beneficiary: address(recipient2), _amount: type(uint256).max});
        assertEq(IERC20(testToken).balanceOf(splitLock.vault), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), amount);

        assertEq(govNFT.unclaimed(splitToken), 0);
        assertEq(govNFT.unclaimed(from), 0);
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
        emit IGovNFT.Sweep({tokenId: tokenId, token: airdropToken, recipient: testUser, amount: TOKEN_100K});
        govNFT.sweep({_tokenId: tokenId, _token: airdropToken, _recipient: testUser});

        assertEq(IERC20(airdropToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(airdropToken).balanceOf(vault), 0);
        assertEq(IERC20(airdropToken).balanceOf(address(admin)), 0);
        assertEq(IERC20(airdropToken).balanceOf(address(recipient)), 0);
        assertEq(IERC20(airdropToken).balanceOf(testUser), TOKEN_100K);
    }

    function test_SweepAfterClaim() public {
        airdropper.transfer(testToken, vault, TOKEN_100K);
        IGovNFT.Lock memory lock = govNFT.locks(tokenId);

        skip(WEEK * 2); //skip to the vesting end timestamp

        vm.prank(address(recipient));
        govNFT.claim({_tokenId: tokenId, _beneficiary: address(recipient), _amount: lock.totalLocked});

        assertEq(IERC20(testToken).balanceOf(vault), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), TOKEN_100K);
        lock = govNFT.locks(tokenId);
        assertEq(lock.totalClaimed, lock.totalLocked);
        assertEq(govNFT.unclaimed(tokenId), 0);

        vm.prank(address(recipient));
        govNFT.sweep({_tokenId: tokenId, _token: testToken, _recipient: address(recipient)});

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
            cliff: WEEK / 2,
            description: ""
        });
        uint256 splitToken = govNFT.split(tokenId, paramsList)[0];

        // Can only sweep airdropped amount on Parent Token
        assertEq(IERC20(testToken).balanceOf(vault), TOKEN_100K + (lock.totalLocked - amount));
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);

        govNFT.sweep({_tokenId: tokenId, _token: testToken, _recipient: address(recipient)});

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
        govNFT.sweep({_tokenId: splitToken, _token: testToken, _recipient: address(recipient2)});

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
            cliff: 0,
            description: ""
        });
        uint256 splitToken = govNFT.split(tokenId, paramsList)[0];

        // Can only sweep airdropped amount on Parent Token
        uint256 unclaimedAmount = govNFT.unclaimed(tokenId);
        uint256 totalLocked = govNFT.locks(tokenId).totalLocked;
        assertEq(IERC20(testToken).balanceOf(vault), TOKEN_100K + (totalLocked + unclaimedAmount));
        assertEq(lock.initialDeposit, totalLocked + unclaimedAmount + amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);

        govNFT.sweep({_tokenId: tokenId, _token: testToken, _recipient: address(recipient)});

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
        govNFT.sweep({_tokenId: splitToken, _token: testToken, _recipient: address(recipient2)});

        assertEq(IERC20(testToken).balanceOf(splitVault), amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);

        // Can claim all vested tokens as expected
        _checkClaimsAfterSweeps(tokenId, splitToken, amount);
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
            cliff: 0,
            description: ""
        });
        uint256 tokenId2 = govNFT.split(tokenId, paramsList)[0];

        uint256 unclaimedAmount = govNFT.unclaimed(tokenId);

        vm.expectRevert(IGovNFT.ZeroAmount.selector);
        govNFT.sweep({_tokenId: tokenId, _token: testToken, _recipient: address(recipient)});

        assertEqUint(IERC20(testToken).balanceOf(address(recipient)), 0);
        govNFT.claim({_tokenId: tokenId, _beneficiary: address(recipient), _amount: type(uint256).max});
        assertEqUint(IERC20(testToken).balanceOf(address(recipient)), unclaimedAmount);

        unclaimedAmount = govNFT.unclaimed(tokenId2);

        vm.startPrank(address(recipient2));
        vm.expectRevert(IGovNFT.ZeroAmount.selector);
        govNFT.sweep({_tokenId: tokenId2, _token: testToken, _recipient: address(recipient2)});

        assertEqUint(IERC20(testToken).balanceOf(address(recipient2)), 0);
        govNFT.claim({_tokenId: tokenId2, _beneficiary: address(recipient2), _amount: type(uint256).max});
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
        emit IGovNFT.Sweep({tokenId: tokenId, token: airdropToken, recipient: approvedUser, amount: TOKEN_1});
        govNFT.sweep({_tokenId: tokenId, _token: airdropToken, _recipient: approvedUser, _amount: TOKEN_1});
        assertEq(IERC20(airdropToken).balanceOf(approvedUser), TOKEN_1);

        address approvedForAllUser = makeAddr("bob");
        assertEq(IERC20(testToken).balanceOf(approvedForAllUser), 0);

        vm.prank(address(recipient));
        govNFT.setApprovalForAll(approvedForAllUser, true);

        // can sweep after getting approval for all nfts
        vm.prank(approvedForAllUser);
        vm.expectEmit(true, true, true, true, address(govNFT));
        emit IGovNFT.Sweep({tokenId: tokenId, token: airdropToken, recipient: approvedForAllUser, amount: TOKEN_1});
        govNFT.sweep({_tokenId: tokenId, _token: airdropToken, _recipient: approvedForAllUser, _amount: TOKEN_1});
        assertEq(IERC20(airdropToken).balanceOf(approvedForAllUser), TOKEN_1);
    }
}
