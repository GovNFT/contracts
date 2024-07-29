// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract FrozenTest is BaseTest {
    uint256 public tokenId;
    uint256 public timelock = 1 days;
    IGovNFTTimelock public govNFTTimelock;

    function _setUp() public override {
        address vaultImplementation = address(new Vault());
        GovNFTTimelockFactory factory = new GovNFTTimelockFactory({
            _vaultImplementation: vaultImplementation,
            _artProxy: address(artProxy),
            _name: NAME,
            _symbol: SYMBOL,
            _timelock: timelock
        });
        govNFTTimelock = GovNFTTimelock(factory.govNFT());

        skip(WEEK); //skip to the vesting end timestamp

        deal(testToken, address(admin), TOKEN_10M);
        admin.approve(testToken, address(govNFTTimelock), TOKEN_10M);
        vm.prank(address(admin));
        tokenId = govNFTTimelock.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_10M,
            _startTime: 0,
            _endTime: WEEK,
            _cliffLength: 0,
            _description: ""
        });
    }

    function test_Unfreeze() public {
        vm.prank(address(recipient));
        govNFTTimelock.freeze({_tokenId: tokenId});
        IGovNFTTimelock.Frozen memory frozenState = govNFTTimelock.frozenState(tokenId);
        assertTrue(frozenState.isFrozen);
        assertEq(frozenState.timestamp, block.timestamp);

        vm.expectEmit(address(govNFTTimelock));
        emit IGovNFTTimelock.Unfreeze({tokenId: tokenId});
        vm.prank(address(recipient));
        govNFTTimelock.unfreeze({_tokenId: tokenId});

        frozenState = govNFTTimelock.frozenState(tokenId);
        assertEq(frozenState.isFrozen, false);
        assertEq(frozenState.timestamp, 0);
    }

    function test_RevertIf_UnfreezeAlreadyUnfrozen() public {
        vm.prank(address(recipient));
        vm.expectRevert(IGovNFTTimelock.AlreadyIntendedUnfrozen.selector);
        govNFTTimelock.unfreeze({_tokenId: tokenId});

        IGovNFTTimelock.Frozen memory frozenState = govNFTTimelock.frozenState(tokenId);
        assertEq(frozenState.isFrozen, false);
        assertEq(frozenState.timestamp, 0);
    }

    function test_ClaimUnfrozen() public {
        IGovNFT.Lock memory lock = govNFTTimelock.locks(tokenId);

        IGovNFTTimelock.Frozen memory frozenState = govNFTTimelock.frozenState(tokenId);
        assertEq(frozenState.isFrozen, false);
        assertEq(frozenState.timestamp, 0);

        vm.expectEmit(true, true, true, true, address(govNFTTimelock));
        emit IGovNFT.Claim({tokenId: tokenId, recipient: address(recipient), claimed: lock.totalLocked});
        vm.prank(address(recipient));
        govNFTTimelock.claim({_tokenId: tokenId, _beneficiary: address(recipient), _amount: lock.totalLocked});

        lock = govNFTTimelock.locks(tokenId);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), lock.totalLocked);

        frozenState = govNFTTimelock.frozenState(tokenId);
        assertEq(frozenState.isFrozen, false);
        assertEq(frozenState.timestamp, 0);
    }

    function test_RevertIf_ClaimFrozen() public {
        IGovNFT.Lock memory lock = govNFTTimelock.locks(tokenId);

        vm.prank(address(recipient));
        govNFTTimelock.freeze({_tokenId: tokenId});

        IGovNFTTimelock.Frozen memory frozenState = govNFTTimelock.frozenState(tokenId);
        assertTrue(frozenState.isFrozen);
        assertEq(frozenState.timestamp, block.timestamp);

        vm.prank(address(recipient));
        vm.expectRevert(IGovNFTTimelock.FrozenToken.selector);
        govNFTTimelock.claim({_tokenId: tokenId, _beneficiary: address(recipient), _amount: lock.totalLocked});

        lock = govNFTTimelock.locks(tokenId);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);
        assertEq(lock.totalLocked, TOKEN_10M);
        assertEq(lock.totalClaimed, 0);

        frozenState = govNFTTimelock.frozenState(tokenId);
        assertTrue(frozenState.isFrozen);
        assertEq(frozenState.timestamp, block.timestamp);
    }

    function test_SweepUnfrozen() public {
        IGovNFT.Lock memory lock = govNFTTimelock.locks(tokenId);

        IGovNFTTimelock.Frozen memory frozenState = govNFTTimelock.frozenState(tokenId);
        assertEq(frozenState.isFrozen, false);
        assertEq(frozenState.timestamp, 0);

        //airdrop 100K tokens to the govNFT's vault
        airdropper.transfer(testToken, lock.vault, TOKEN_100K);

        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);
        assertEq(IERC20(testToken).balanceOf(lock.vault), TOKEN_100K + lock.totalLocked);

        vm.expectEmit(true, true, true, true, address(govNFTTimelock));
        emit IGovNFT.Sweep({tokenId: tokenId, token: testToken, recipient: address(recipient), amount: TOKEN_100K});
        vm.prank(address(recipient));
        govNFTTimelock.sweep({_tokenId: tokenId, _token: testToken, _recipient: address(recipient)});

        assertEq(IERC20(testToken).balanceOf(address(recipient)), TOKEN_100K);
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked);

        frozenState = govNFTTimelock.frozenState(tokenId);
        assertEq(frozenState.isFrozen, false);
        assertEq(frozenState.timestamp, 0);
    }

    function test_RevertIf_SweepFrozen() public {
        vm.prank(address(recipient));
        govNFTTimelock.freeze({_tokenId: tokenId});

        IGovNFTTimelock.Frozen memory frozenState = govNFTTimelock.frozenState(tokenId);

        assertTrue(frozenState.isFrozen);
        assertEq(frozenState.timestamp, block.timestamp);

        vm.expectRevert(IGovNFTTimelock.FrozenToken.selector);
        govNFTTimelock.sweep({_tokenId: tokenId, _token: testToken, _recipient: address(recipient)});
    }

    function test_SplitUnfrozen() public {
        deal(testToken, address(admin), TOKEN_10M);
        admin.approve(testToken, address(govNFTTimelock), TOKEN_10M);
        vm.prank(address(admin));
        tokenId = govNFTTimelock.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_10M,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp + WEEK),
            _cliffLength: 0,
            _description: ""
        });

        IGovNFTTimelock.Frozen memory frozenState = govNFTTimelock.frozenState(tokenId);
        assertEq(frozenState.isFrozen, false);
        assertEq(frozenState.timestamp, 0);

        IGovNFT.Lock memory lockBeforeSplit = govNFTTimelock.locks(tokenId);

        IGovNFT.SplitParams[] memory splitParams = new IGovNFT.SplitParams[](1);
        splitParams[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            start: uint40(block.timestamp),
            end: uint40(block.timestamp + WEEK),
            cliff: 0,
            amount: lockBeforeSplit.totalLocked / 2,
            description: ""
        });

        vm.expectEmit(true, true, true, true, address(govNFTTimelock));
        emit IGovNFT.Split({
            from: tokenId,
            to: tokenId + 1,
            recipient: address(recipient2),
            splitAmount1: lockBeforeSplit.totalLocked / 2,
            splitAmount2: lockBeforeSplit.totalLocked / 2,
            startTime: uint40(block.timestamp),
            endTime: uint40(block.timestamp + WEEK),
            description: ""
        });
        vm.prank(address(recipient));
        govNFTTimelock.split(tokenId, splitParams);

        IGovNFT.Lock memory lockAfterSplit = govNFTTimelock.locks(tokenId);
        assertEq(lockAfterSplit.totalLocked, lockBeforeSplit.totalLocked / 2);

        IGovNFT.Lock memory lockAfterSplit2 = govNFTTimelock.locks(tokenId + 1);
        assertEq(lockAfterSplit2.totalLocked, lockBeforeSplit.totalLocked / 2);

        frozenState = govNFTTimelock.frozenState(tokenId);
        assertEq(frozenState.isFrozen, false);
        assertEq(frozenState.timestamp, 0);
    }

    function test_RevertIf_SplitFrozen() public {
        deal(testToken, address(admin), TOKEN_10M);
        admin.approve(testToken, address(govNFTTimelock), TOKEN_10M);
        vm.prank(address(admin));
        tokenId = govNFTTimelock.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_10M,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp + WEEK),
            _cliffLength: 0,
            _description: ""
        });

        vm.prank(address(recipient));
        govNFTTimelock.freeze({_tokenId: tokenId});

        IGovNFTTimelock.Frozen memory frozenState = govNFTTimelock.frozenState(tokenId);
        assertTrue(frozenState.isFrozen);
        assertEq(frozenState.timestamp, block.timestamp);

        IGovNFT.Lock memory lockBeforeSplit = govNFTTimelock.locks(tokenId);

        IGovNFT.SplitParams[] memory splitParams = new IGovNFT.SplitParams[](1);
        splitParams[0] = IGovNFT.SplitParams({
            beneficiary: address(recipient2),
            start: uint40(block.timestamp),
            end: uint40(block.timestamp + WEEK),
            cliff: 0,
            amount: lockBeforeSplit.totalLocked / 2,
            description: ""
        });

        vm.expectRevert(IGovNFTTimelock.FrozenToken.selector);
        vm.prank(address(recipient));
        govNFTTimelock.split(tokenId, splitParams);

        IGovNFT.Lock memory lockAfterFailedSplit = govNFTTimelock.locks(tokenId);
        assertEq(lockBeforeSplit.totalLocked, lockAfterFailedSplit.totalLocked);

        frozenState = govNFTTimelock.frozenState(tokenId);
        assertTrue(frozenState.isFrozen);
        assertEq(frozenState.timestamp, block.timestamp);
    }

    function test_RevertIf_SplitFullFrozen() public {
        deal(testToken, address(admin), TOKEN_10M);
        admin.approve(testToken, address(govNFTTimelock), TOKEN_10M);
        vm.prank(address(admin));
        tokenId = govNFTTimelock.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_10M,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp + WEEK),
            _cliffLength: 0,
            _description: ""
        });

        vm.prank(address(recipient));
        govNFTTimelock.freeze({_tokenId: tokenId});

        IGovNFTTimelock.Frozen memory frozenState = govNFTTimelock.frozenState(tokenId);
        assertTrue(frozenState.isFrozen);
        assertEq(frozenState.timestamp, block.timestamp);

        IGovNFT.Lock memory lockBeforeSplit = govNFTTimelock.locks(tokenId);

        vm.expectRevert(IGovNFTTimelock.FrozenToken.selector);
        vm.prank(address(recipient));
        govNFTTimelock.split(tokenId);

        IGovNFT.Lock memory lockAfterFailedSplit = govNFTTimelock.locks(tokenId);
        assertEq(lockBeforeSplit.totalLocked, lockAfterFailedSplit.totalLocked);
        assertEq(lockBeforeSplit.vault, lockAfterFailedSplit.vault);
        assertEq(IERC20(lockBeforeSplit.token).balanceOf(lockBeforeSplit.vault), lockBeforeSplit.totalLocked);

        frozenState = govNFTTimelock.frozenState(tokenId);
        assertTrue(frozenState.isFrozen);
        assertEq(frozenState.timestamp, block.timestamp);
    }

    function test_TransferFrozen() public {
        vm.prank(address(recipient));
        govNFTTimelock.freeze({_tokenId: tokenId});

        //skip to end of timelock where NFT is effectively frozen
        skip(govNFTTimelock.timelock());

        IGovNFTTimelock.Frozen memory frozenState = govNFTTimelock.frozenState(tokenId);
        assertTrue(frozenState.isFrozen);
        assertEq(frozenState.timestamp, block.timestamp - govNFTTimelock.timelock());
        assertEq(IERC721(address(govNFTTimelock)).ownerOf(tokenId), address(recipient));

        vm.prank(address(recipient));
        IERC721(address(govNFTTimelock)).safeTransferFrom(address(recipient), address(recipient2), tokenId);

        frozenState = govNFTTimelock.frozenState(tokenId);
        assertEq(frozenState.isFrozen, false);
        assertEq(frozenState.timestamp, 0);
        assertEq(IERC721(address(govNFTTimelock)).ownerOf(tokenId), address(recipient2));
    }

    function test_RevertIf_TransferUnfrozen() public {
        IGovNFTTimelock.Frozen memory frozenState = govNFTTimelock.frozenState(tokenId);
        assertEq(frozenState.isFrozen, false);
        assertEq(frozenState.timestamp, 0);
        assertEq(IERC721(address(govNFTTimelock)).ownerOf(tokenId), address(recipient));

        vm.expectRevert(IGovNFTTimelock.UnfrozenToken.selector);
        vm.prank(address(recipient));
        IERC721(address(govNFTTimelock)).safeTransferFrom(address(recipient), address(recipient2), tokenId);

        frozenState = govNFTTimelock.frozenState(tokenId);
        assertEq(frozenState.isFrozen, false);
        assertEq(frozenState.timestamp, 0);
        assertEq(IERC721(address(govNFTTimelock)).ownerOf(tokenId), address(recipient));
    }

    function test_RevertIf_TransferInTimelock() public {
        IGovNFTTimelock.Frozen memory frozenState = govNFTTimelock.frozenState(tokenId);
        assertEq(frozenState.isFrozen, false);
        assertEq(frozenState.timestamp, 0);

        vm.prank(address(recipient));
        govNFTTimelock.freeze({_tokenId: tokenId});

        frozenState = govNFTTimelock.frozenState(tokenId);
        assertTrue(frozenState.isFrozen);
        assertEq(frozenState.timestamp, block.timestamp);
        assertEq(IERC721(address(govNFTTimelock)).ownerOf(tokenId), address(recipient));

        vm.expectRevert(IGovNFTTimelock.UnfrozenToken.selector);
        vm.prank(address(recipient));
        IERC721(address(govNFTTimelock)).safeTransferFrom(address(recipient), address(recipient2), tokenId);

        assertEq(IERC721(address(govNFTTimelock)).ownerOf(tokenId), address(recipient));

        skip(govNFTTimelock.timelock() - 1);

        vm.expectRevert(IGovNFTTimelock.UnfrozenToken.selector);
        vm.prank(address(recipient));
        IERC721(address(govNFTTimelock)).safeTransferFrom(address(recipient), address(recipient2), tokenId);

        frozenState = govNFTTimelock.frozenState(tokenId);
        assertTrue(frozenState.isFrozen);
        assertGt(frozenState.timestamp + govNFTTimelock.timelock(), block.timestamp);
        assertEq(IERC721(address(govNFTTimelock)).ownerOf(tokenId), address(recipient));
    }
}
