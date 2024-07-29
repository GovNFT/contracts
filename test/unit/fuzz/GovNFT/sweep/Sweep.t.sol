// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract SweepUnitFuzzTest is BaseTest {
    uint256 public tokenId;
    address public vault;

    /// @dev Parameters used for Sweep calls
    address public tokenToSweep;
    uint256 public airdropAmount;
    address public sweepRecipient;

    function _setUp() public override {
        _createInitialLock();
    }

    function _createInitialLock() internal {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.startPrank(address(admin));
        tokenId = govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_100K,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 2,
            _cliffLength: WEEK,
            _description: ""
        });
        vm.stopPrank();

        vault = govNFT.locks(tokenId).vault;
    }

    modifier whenTokenIsNotAddressZero() {
        tokenToSweep = airdropToken;
        _;
    }

    modifier whenRecipientIsNotAddressZero() {
        sweepRecipient = address(recipient2);
        _;
    }

    function testFuzz_WhenCallerIsNotAuthorized(
        address caller
    ) external whenTokenIsNotAddressZero whenRecipientIsNotAddressZero {
        vm.assume(caller != address(recipient) && caller != address(0));

        // It should revert with ERC721InsufficientApproval
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, caller, tokenId));
        vm.prank(caller);
        govNFT.sweep({_tokenId: tokenId, _token: tokenToSweep, _recipient: sweepRecipient});
    }

    modifier whenCallerIsAuthorized() {
        vm.startPrank(address(recipient));
        _;
    }

    modifier whenTokenToSweepIsLockToken() {
        tokenToSweep = testToken;
        _;
    }

    modifier givenEarlySweepingOfLockTokensIsDisabled() {
        // Overwrite `govNFT` with new GovNFT that disables early sweeping
        govNFT = GovNFT(
            factory.createGovNFT({
                _owner: address(admin),
                _artProxy: address(artProxy),
                _name: NAME,
                _symbol: SYMBOL,
                _earlySweepLockToken: false
            })
        );
        assertFalse(govNFT.earlySweepLockToken());

        deal(tokenToSweep, address(admin), TOKEN_100K);
        _createInitialLock();
        vm.startPrank(address(recipient));
        _;
    }

    modifier givenLockFinishedVesting() {
        // Warp to Lock End
        vm.warp(govNFT.locks(tokenId).end);
        _;
    }

    modifier whenAmountToSweepIsNotZero() {
        _;
    }

    modifier givenVaultHasAdditionalLockTokenBalance(uint256 amountToAirdrop) {
        airdropAmount = bound(amountToAirdrop, 2, MAX_TOKENS);
        // Airdrop Lock tokens to Vault
        deal(tokenToSweep, vault, IERC20(tokenToSweep).balanceOf(vault) + airdropAmount);

        // Assert Balances
        assertEq(IERC20(tokenToSweep).balanceOf(vault), govNFT.locks(tokenId).totalLocked + airdropAmount);
        assertEq(IERC20(tokenToSweep).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(tokenToSweep).balanceOf(sweepRecipient), 0);
        _;
    }

    function testFuzz_WhenAmountToSweepIsSmallerThanAdditionalBalance(
        uint256 amountToAirdrop,
        uint256 sweepAmount
    )
        external
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenCallerIsAuthorized
        whenTokenToSweepIsLockToken
        givenEarlySweepingOfLockTokensIsDisabled
        givenLockFinishedVesting
        whenAmountToSweepIsNotZero
        givenVaultHasAdditionalLockTokenBalance(amountToAirdrop)
    {
        uint256 vaultBalance = IERC20(tokenToSweep).balanceOf(vault);

        sweepAmount = bound(sweepAmount, 1, airdropAmount - 1);

        // It should sweep amount to recipient
        // It should emit a {Sweep} event
        vm.expectEmit(address(govNFT));
        emit IGovNFT.Sweep({tokenId: tokenId, token: tokenToSweep, recipient: sweepRecipient, amount: sweepAmount});
        govNFT.sweep({_tokenId: tokenId, _token: tokenToSweep, _recipient: sweepRecipient, _amount: sweepAmount});

        assertEq(IERC20(tokenToSweep).balanceOf(vault), vaultBalance - sweepAmount);
        assertEq(IERC20(tokenToSweep).balanceOf(sweepRecipient), sweepAmount);
        assertEq(IERC20(tokenToSweep).balanceOf(address(govNFT)), 0);
    }

    function testFuzz_WhenAmountToSweepIsEqualOrGreaterThanAdditionalBalance(
        uint256 amountToAirdrop,
        uint256 sweepAmount
    )
        external
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenCallerIsAuthorized
        whenTokenToSweepIsLockToken
        givenEarlySweepingOfLockTokensIsDisabled
        givenLockFinishedVesting
        whenAmountToSweepIsNotZero
        givenVaultHasAdditionalLockTokenBalance(amountToAirdrop)
    {
        uint256 vaultBalance = IERC20(tokenToSweep).balanceOf(vault);
        uint256 additionalBal = vaultBalance - govNFT.locks(tokenId).totalLocked;

        // It should sweep amount to recipient
        // It should emit a {Sweep} event
        sweepAmount = bound(sweepAmount, additionalBal, type(uint256).max);
        vm.expectEmit(address(govNFT));
        emit IGovNFT.Sweep({tokenId: tokenId, token: tokenToSweep, recipient: sweepRecipient, amount: additionalBal});
        govNFT.sweep({_tokenId: tokenId, _token: tokenToSweep, _recipient: sweepRecipient, _amount: sweepAmount});

        assertEq(IERC20(tokenToSweep).balanceOf(vault), vaultBalance - additionalBal);
        assertEq(IERC20(tokenToSweep).balanceOf(sweepRecipient), additionalBal);
        assertEq(IERC20(tokenToSweep).balanceOf(address(govNFT)), 0);
    }

    modifier givenEarlySweepingOfLockTokensIsEnabled() {
        // Early sweep is enabled in default GovNFT
        assertTrue(govNFT.earlySweepLockToken());
        _;
    }

    modifier whenAmountToSweepIsNotZero_() {
        _;
    }

    modifier givenVaultHasAdditionalLockTokenBalance_(uint256 amountToAirdrop) {
        airdropAmount = bound(amountToAirdrop, 2, MAX_TOKENS);
        // Airdrop Lock tokens to Vault
        deal(tokenToSweep, vault, IERC20(tokenToSweep).balanceOf(vault) + airdropAmount);

        // Assert Balances
        assertEq(IERC20(tokenToSweep).balanceOf(vault), govNFT.locks(tokenId).totalLocked + airdropAmount);
        assertEq(IERC20(tokenToSweep).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(tokenToSweep).balanceOf(sweepRecipient), 0);
        _;
    }

    function testFuzz_WhenAmountToSweepIsSmallerThanAdditionalBalance_(
        uint256 amountToAirdrop,
        uint256 sweepAmount
    )
        external
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenCallerIsAuthorized
        whenTokenToSweepIsLockToken
        givenEarlySweepingOfLockTokensIsEnabled
        whenAmountToSweepIsNotZero_
        givenVaultHasAdditionalLockTokenBalance_(amountToAirdrop)
    {
        uint256 vaultBalance = IERC20(tokenToSweep).balanceOf(vault);

        // It should sweep amount to recipient
        // It should emit a {Sweep} event
        sweepAmount = bound(sweepAmount, 1, airdropAmount - 1);
        vm.expectEmit(address(govNFT));
        emit IGovNFT.Sweep({tokenId: tokenId, token: tokenToSweep, recipient: sweepRecipient, amount: sweepAmount});
        govNFT.sweep({_tokenId: tokenId, _token: tokenToSweep, _recipient: sweepRecipient, _amount: sweepAmount});

        assertEq(IERC20(tokenToSweep).balanceOf(vault), vaultBalance - sweepAmount);
        assertEq(IERC20(tokenToSweep).balanceOf(sweepRecipient), sweepAmount);
        assertEq(IERC20(tokenToSweep).balanceOf(address(govNFT)), 0);
    }

    function testFuzz_WhenAmountToSweepIsEqualOrGreaterThanAdditionalBalance_(
        uint256 amountToAirdrop,
        uint256 sweepAmount
    )
        external
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenCallerIsAuthorized
        whenTokenToSweepIsLockToken
        givenEarlySweepingOfLockTokensIsEnabled
        whenAmountToSweepIsNotZero_
        givenVaultHasAdditionalLockTokenBalance_(amountToAirdrop)
    {
        uint256 vaultBalance = IERC20(tokenToSweep).balanceOf(vault);
        uint256 additionalBal = vaultBalance - govNFT.locks(tokenId).totalLocked;

        // It should sweep additional balance to recipient
        // It should emit a {Sweep} event
        sweepAmount = bound(sweepAmount, additionalBal, type(uint256).max);
        vm.expectEmit(address(govNFT));
        emit IGovNFT.Sweep({tokenId: tokenId, token: tokenToSweep, recipient: sweepRecipient, amount: additionalBal});
        govNFT.sweep({_tokenId: tokenId, _token: tokenToSweep, _recipient: sweepRecipient, _amount: sweepAmount});

        assertEq(IERC20(tokenToSweep).balanceOf(vault), vaultBalance - additionalBal);
        assertEq(IERC20(tokenToSweep).balanceOf(sweepRecipient), additionalBal);
        assertEq(IERC20(tokenToSweep).balanceOf(address(govNFT)), 0);
    }

    modifier whenTokenToSweepIsNotLockToken() {
        tokenToSweep = airdropToken;
        _;
    }

    modifier whenAmountToSweepIsNotZero__() {
        _;
    }

    modifier givenVaultBalanceIsNotZero(uint256 amountToAirdrop) {
        airdropAmount = bound(amountToAirdrop, 1, MAX_TOKENS);

        // Airdrop tokens to Vault
        deal(tokenToSweep, vault, airdropAmount);

        // Assert Balances
        assertEq(IERC20(tokenToSweep).balanceOf(sweepRecipient), 0);
        assertEq(IERC20(tokenToSweep).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(tokenToSweep).balanceOf(vault), airdropAmount);
        _;
    }

    function testFuzz_GivenAmountIsSmallerThanVaultBalance(
        uint256 amountToAirdrop,
        uint256 sweepAmount
    )
        external
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenCallerIsAuthorized
        whenTokenToSweepIsNotLockToken
        whenAmountToSweepIsNotZero__
        givenVaultBalanceIsNotZero(amountToAirdrop)
    {
        airdropAmount += 1; // increase `airdropAmount` by 1 to allow `sweepAmount` to be smaller
        sweepAmount = bound(sweepAmount, 1, airdropAmount - 1);
        uint256 vaultBalance = IERC20(tokenToSweep).balanceOf(vault);

        // It should sweep amount to recipient
        // It should emit a {Sweep} event
        vm.expectEmit(address(govNFT));
        emit IGovNFT.Sweep({tokenId: tokenId, token: tokenToSweep, recipient: sweepRecipient, amount: sweepAmount});
        govNFT.sweep({_tokenId: tokenId, _token: tokenToSweep, _recipient: sweepRecipient, _amount: sweepAmount});

        assertEq(IERC20(tokenToSweep).balanceOf(vault), vaultBalance - sweepAmount);
        assertEq(IERC20(tokenToSweep).balanceOf(sweepRecipient), sweepAmount);
        assertEq(IERC20(tokenToSweep).balanceOf(address(govNFT)), 0);
    }

    function testFuzz_GivenAmountIsEqualOrGreaterThanVaultBalance(
        uint256 amountToAirdrop,
        uint256 sweepAmount
    )
        external
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenCallerIsAuthorized
        whenTokenToSweepIsNotLockToken
        whenAmountToSweepIsNotZero__
        givenVaultBalanceIsNotZero(amountToAirdrop)
    {
        sweepAmount = bound(sweepAmount, airdropAmount, type(uint256).max);
        uint256 vaultBalance = IERC20(tokenToSweep).balanceOf(vault);

        // It should sweep vault balance to recipient
        // It should emit a {Sweep} event
        vm.expectEmit(address(govNFT));
        emit IGovNFT.Sweep({tokenId: tokenId, token: tokenToSweep, recipient: sweepRecipient, amount: vaultBalance});
        govNFT.sweep({_tokenId: tokenId, _token: tokenToSweep, _recipient: sweepRecipient, _amount: sweepAmount});

        assertEq(IERC20(tokenToSweep).balanceOf(vault), 0);
        assertEq(IERC20(tokenToSweep).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(tokenToSweep).balanceOf(sweepRecipient), vaultBalance);
    }

    function testFuzz_SweepPartial(uint256 amount) public {
        airdropper.transfer(airdropToken, vault, TOKEN_100K);
        amount = bound(amount, 1, TOKEN_100K);
        uint256 amountLeftToSweep = TOKEN_100K;

        uint256 amountSwept;
        uint256 cycles; //prevent long running tests
        while (amountLeftToSweep > 0 && cycles < 20) {
            if (amount > amountLeftToSweep) amount = amountLeftToSweep;
            amountSwept += amount;

            vm.prank(address(recipient));
            vm.expectEmit(true, true, true, true, address(govNFT));
            emit IGovNFT.Sweep({tokenId: tokenId, token: airdropToken, recipient: address(recipient), amount: amount});
            govNFT.sweep({_tokenId: tokenId, _token: airdropToken, _recipient: address(recipient), _amount: amount});

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
            govNFT.sweep({_tokenId: tokenId, _token: testToken, _recipient: address(recipient)});
            balanceRecipient += TOKEN_100K;

            vm.prank(address(recipient));
            govNFT.claim({_tokenId: tokenId, _beneficiary: address(recipient), _amount: lock.totalLocked});

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
        govNFT.sweep({_tokenId: tokenId, _token: testToken, _recipient: address(recipient), _amount: amount});

        assertEq(IERC20(testToken).balanceOf(vault), lock.totalLocked + TOKEN_100K - amount);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), amount);
        lock = govNFT.locks(tokenId);
        assertEq(lock.totalClaimed, 0);
        assertEq(govNFT.unclaimed(tokenId), expectedClaim);

        //check user can stil claim lock
        vm.prank(address(recipient));
        govNFT.claim({_tokenId: tokenId, _beneficiary: address(recipient), _amount: lock.totalLocked});

        assertEq(IERC20(testToken).balanceOf(vault), lock.totalLocked + TOKEN_100K - expectedClaim - amount);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), amount + expectedClaim);
        lock = govNFT.locks(tokenId);
        assertEq(lock.totalClaimed, expectedClaim);
        assertEq(govNFT.unclaimed(tokenId), 0);
    }

    function testFuzz_SweepAfterSplit(uint256 amount, uint40 timeskip) public {
        deal(testToken, address(admin), TOKEN_100K);
        vm.startPrank(address(admin));
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        uint256 from = govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_100K,
            _startTime: uint40(block.timestamp) + WEEK,
            _endTime: uint40(block.timestamp) + WEEK * 4,
            _cliffLength: WEEK,
            _description: ""
        });
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
            cliff: lock.cliffLength,
            description: ""
        });
        uint256 splitToken = govNFT.split(from, paramsList)[0];

        // Can only sweep airdropped amount on Parent Token
        uint256 unclaimedAmount = govNFT.unclaimed(from);
        uint256 totalLocked = govNFT.locks(from).totalLocked;
        assertApproxEqAbs(IERC20(testToken).balanceOf(lock.vault), TOKEN_100K + (totalLocked + unclaimedAmount), 2);
        assertEq(lock.initialDeposit, totalLocked + unclaimedAmount + amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);

        govNFT.sweep({_tokenId: from, _token: testToken, _recipient: address(recipient)});

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
        govNFT.sweep({_tokenId: splitToken, _token: testToken, _recipient: address(recipient2)});

        assertEq(IERC20(testToken).balanceOf(splitVault), amount);
        assertEq(IERC20(testToken).balanceOf(address(recipient2)), 0);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);

        // Can claim all vested tokens as expected
        _checkClaimsAfterSweeps(from, splitToken, amount);
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
            cliff: lock.cliffLength,
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
        govNFT.claim({_tokenId: tokenId2, _beneficiary: address(recipient), _amount: type(uint256).max});
        assertEqUint(IERC20(testToken).balanceOf(address(recipient2)), unclaimedAmount);
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
}
