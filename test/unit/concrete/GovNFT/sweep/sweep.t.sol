// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract SweepUnitConcreteTest is BaseTest {
    uint256 public tokenId;
    address public vault;

    /// @dev Parameters used for Sweep calls
    address public tokenToSweep;
    uint256 public amountToSweep;
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

    function test_WhenTokenIsAddressZero() external {
        // It should revert with ZeroAddress
        vm.expectRevert(IGovNFT.ZeroAddress.selector);
        vm.prank(address(recipient));
        govNFT.sweep({_tokenId: tokenId, _token: tokenToSweep, _recipient: sweepRecipient});
    }

    modifier whenTokenIsNotAddressZero() {
        tokenToSweep = airdropToken;
        _;
    }

    function test_WhenRecipientIsAddressZero() external whenTokenIsNotAddressZero {
        // It should revert with ZeroAddress
        vm.expectRevert(IGovNFT.ZeroAddress.selector);
        vm.prank(address(recipient));
        govNFT.sweep({_tokenId: tokenId, _token: tokenToSweep, _recipient: sweepRecipient});
    }

    modifier whenRecipientIsNotAddressZero() {
        sweepRecipient = address(recipient2);
        _;
    }

    function test_WhenCallerIsNotAuthorized() external whenTokenIsNotAddressZero whenRecipientIsNotAddressZero {
        // It should revert with ERC721InsufficientApproval
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(recipient2), tokenId)
        );
        vm.prank(address(recipient2));
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

    function test_GivenLockDidNotFinishVesting()
        external
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenCallerIsAuthorized
        whenTokenToSweepIsLockToken
        givenEarlySweepingOfLockTokensIsDisabled
    {
        // It should revert with InvalidSweep
        vm.expectRevert(abi.encodeWithSelector(IGovNFT.InvalidSweep.selector));
        govNFT.sweep({_tokenId: tokenId, _token: tokenToSweep, _recipient: sweepRecipient});
    }

    modifier givenLockFinishedVesting() {
        // Warp to Lock End
        vm.warp(govNFT.locks(tokenId).end);
        _;
    }

    function test_WhenAmountToSweepIsZero()
        external
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenCallerIsAuthorized
        whenTokenToSweepIsLockToken
        givenEarlySweepingOfLockTokensIsDisabled
        givenLockFinishedVesting
    {
        // It should revert with ZeroAmount
        vm.expectRevert(abi.encodeWithSelector(IGovNFT.ZeroAmount.selector));
        govNFT.sweep({_tokenId: tokenId, _token: tokenToSweep, _recipient: sweepRecipient, _amount: amountToSweep});
    }

    modifier whenAmountToSweepIsNotZero() {
        amountToSweep = type(uint256).max;
        _;
    }

    function test_GivenVaultOnlyHasLockBalance()
        external
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenCallerIsAuthorized
        whenTokenToSweepIsLockToken
        givenEarlySweepingOfLockTokensIsDisabled
        givenLockFinishedVesting
        whenAmountToSweepIsNotZero
    {
        // It should revert with ZeroAmount
        vm.expectRevert(abi.encodeWithSelector(IGovNFT.ZeroAmount.selector));
        govNFT.sweep({_tokenId: tokenId, _token: tokenToSweep, _recipient: sweepRecipient, _amount: amountToSweep});
    }

    modifier givenVaultHasAdditionalLockTokenBalance() {
        // Airdrop Lock tokens to Vault
        deal(tokenToSweep, vault, IERC20(tokenToSweep).balanceOf(vault) + TOKEN_100K);

        // Assert Balances
        assertEq(IERC20(tokenToSweep).balanceOf(vault), govNFT.locks(tokenId).totalLocked + TOKEN_100K);
        assertEq(IERC20(tokenToSweep).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(tokenToSweep).balanceOf(sweepRecipient), 0);
        _;
    }

    function test_WhenAmountToSweepIsSmallerThanAdditionalBalance()
        external
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenCallerIsAuthorized
        whenTokenToSweepIsLockToken
        givenEarlySweepingOfLockTokensIsDisabled
        givenLockFinishedVesting
        whenAmountToSweepIsNotZero
        givenVaultHasAdditionalLockTokenBalance
    {
        uint256 vaultBalance = IERC20(tokenToSweep).balanceOf(vault);

        // It should sweep amount to recipient
        // It should emit a {Sweep} event
        amountToSweep = vaultBalance / 4;
        vm.expectEmit(address(govNFT));
        emit IGovNFT.Sweep({tokenId: tokenId, token: tokenToSweep, recipient: sweepRecipient, amount: amountToSweep});
        govNFT.sweep({_tokenId: tokenId, _token: tokenToSweep, _recipient: sweepRecipient, _amount: amountToSweep});

        assertEq(IERC20(tokenToSweep).balanceOf(vault), vaultBalance - amountToSweep);
        assertEq(IERC20(tokenToSweep).balanceOf(sweepRecipient), amountToSweep);
        assertEq(IERC20(tokenToSweep).balanceOf(address(govNFT)), 0);
    }

    function test_WhenAmountToSweepIsEqualOrGreaterThanAdditionalBalance()
        external
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenCallerIsAuthorized
        whenTokenToSweepIsLockToken
        givenEarlySweepingOfLockTokensIsDisabled
        givenLockFinishedVesting
        whenAmountToSweepIsNotZero
        givenVaultHasAdditionalLockTokenBalance
    {
        uint256 vaultBalance = IERC20(tokenToSweep).balanceOf(vault);
        uint256 totalLocked = govNFT.locks(tokenId).totalLocked;
        uint256 additionalBal = vaultBalance - totalLocked;

        // It should sweep amount to recipient
        // It should emit a {Sweep} event
        amountToSweep = additionalBal + TOKEN_10K;
        vm.expectEmit(address(govNFT));
        emit IGovNFT.Sweep({tokenId: tokenId, token: tokenToSweep, recipient: sweepRecipient, amount: additionalBal});
        govNFT.sweep({_tokenId: tokenId, _token: tokenToSweep, _recipient: sweepRecipient, _amount: amountToSweep});

        assertEq(IERC20(tokenToSweep).balanceOf(vault), vaultBalance - additionalBal);
        assertEq(IERC20(tokenToSweep).balanceOf(sweepRecipient), additionalBal);
        assertEq(IERC20(tokenToSweep).balanceOf(address(govNFT)), 0);
    }

    modifier givenEarlySweepingOfLockTokensIsEnabled() {
        // Early sweep is enabled in default GovNFT
        assertTrue(govNFT.earlySweepLockToken());
        _;
    }

    function test_WhenAmountToSweepIsZero_()
        external
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenCallerIsAuthorized
        whenTokenToSweepIsLockToken
        givenEarlySweepingOfLockTokensIsEnabled
    {
        // It should revert with ZeroAmount
        vm.expectRevert(abi.encodeWithSelector(IGovNFT.ZeroAmount.selector));
        govNFT.sweep({_tokenId: tokenId, _token: tokenToSweep, _recipient: sweepRecipient, _amount: amountToSweep});
    }

    modifier whenAmountToSweepIsNotZero_() {
        amountToSweep = type(uint256).max;
        _;
    }

    function test_GivenVaultOnlyHasLockBalance_()
        external
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenCallerIsAuthorized
        whenTokenToSweepIsLockToken
        givenEarlySweepingOfLockTokensIsEnabled
        whenAmountToSweepIsNotZero_
    {
        // It should revert with ZeroAmount
        vm.expectRevert(abi.encodeWithSelector(IGovNFT.ZeroAmount.selector));
        govNFT.sweep({_tokenId: tokenId, _token: tokenToSweep, _recipient: sweepRecipient, _amount: amountToSweep});
    }

    modifier givenVaultHasAdditionalLockTokenBalance_() {
        // Airdrop Lock tokens to Vault
        deal(tokenToSweep, vault, IERC20(tokenToSweep).balanceOf(vault) + TOKEN_100K);

        // Assert Balances
        assertEq(IERC20(tokenToSweep).balanceOf(vault), govNFT.locks(tokenId).totalLocked + TOKEN_100K);
        assertEq(IERC20(tokenToSweep).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(tokenToSweep).balanceOf(sweepRecipient), 0);
        _;
    }

    function test_WhenAmountToSweepIsSmallerThanAdditionalBalance_()
        external
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenCallerIsAuthorized
        whenTokenToSweepIsLockToken
        givenEarlySweepingOfLockTokensIsEnabled
        whenAmountToSweepIsNotZero_
        givenVaultHasAdditionalLockTokenBalance_
    {
        uint256 vaultBalance = IERC20(tokenToSweep).balanceOf(vault);

        // It should sweep amount to recipient
        // It should emit a {Sweep} event
        amountToSweep = vaultBalance / 4;
        vm.expectEmit(address(govNFT));
        emit IGovNFT.Sweep({tokenId: tokenId, token: tokenToSweep, recipient: sweepRecipient, amount: amountToSweep});
        govNFT.sweep({_tokenId: tokenId, _token: tokenToSweep, _recipient: sweepRecipient, _amount: amountToSweep});

        assertEq(IERC20(tokenToSweep).balanceOf(vault), vaultBalance - amountToSweep);
        assertEq(IERC20(tokenToSweep).balanceOf(sweepRecipient), amountToSweep);
        assertEq(IERC20(tokenToSweep).balanceOf(address(govNFT)), 0);
    }

    function test_WhenAmountToSweepIsEqualOrGreaterThanAdditionalBalance_()
        external
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenCallerIsAuthorized
        whenTokenToSweepIsLockToken
        givenEarlySweepingOfLockTokensIsEnabled
        whenAmountToSweepIsNotZero_
        givenVaultHasAdditionalLockTokenBalance_
    {
        uint256 vaultBalance = IERC20(tokenToSweep).balanceOf(vault);
        uint256 totalLocked = govNFT.locks(tokenId).totalLocked;
        uint256 additionalBal = vaultBalance - totalLocked;

        // It should sweep additional balance to recipient
        // It should emit a {Sweep} event
        amountToSweep = additionalBal + TOKEN_10K;
        vm.expectEmit(address(govNFT));
        emit IGovNFT.Sweep({tokenId: tokenId, token: tokenToSweep, recipient: sweepRecipient, amount: additionalBal});
        govNFT.sweep({_tokenId: tokenId, _token: tokenToSweep, _recipient: sweepRecipient, _amount: amountToSweep});

        assertEq(IERC20(tokenToSweep).balanceOf(vault), vaultBalance - additionalBal);
        assertEq(IERC20(tokenToSweep).balanceOf(sweepRecipient), additionalBal);
        assertEq(IERC20(tokenToSweep).balanceOf(address(govNFT)), 0);
    }

    modifier whenTokenToSweepIsNotLockToken() {
        tokenToSweep = airdropToken;
        _;
    }

    function test_WhenAmountToSweepIsZero__()
        external
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenCallerIsAuthorized
        whenTokenToSweepIsNotLockToken
    {
        // It should revert with ZeroAmount
        vm.expectRevert(abi.encodeWithSelector(IGovNFT.ZeroAmount.selector));
        govNFT.sweep({_tokenId: tokenId, _token: tokenToSweep, _recipient: sweepRecipient, _amount: amountToSweep});
    }

    modifier whenAmountToSweepIsNotZero__() {
        amountToSweep = type(uint40).max;
        _;
    }

    function test_GivenVaultBalanceIsZero()
        external
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenCallerIsAuthorized
        whenTokenToSweepIsNotLockToken
        whenAmountToSweepIsNotZero__
    {
        // It should revert with ZeroAmount
        vm.expectRevert(abi.encodeWithSelector(IGovNFT.ZeroAmount.selector));
        govNFT.sweep({_tokenId: tokenId, _token: tokenToSweep, _recipient: sweepRecipient, _amount: amountToSweep});
    }

    modifier givenVaultBalanceIsNotZero() {
        // Airdrop tokens to Vault
        deal(tokenToSweep, vault, TOKEN_100K);

        // Assert Balances
        assertEq(IERC20(tokenToSweep).balanceOf(vault), TOKEN_100K);
        assertEq(IERC20(tokenToSweep).balanceOf(sweepRecipient), 0);
        assertEq(IERC20(tokenToSweep).balanceOf(address(govNFT)), 0);
        _;
    }

    function test_GivenAmountIsSmallerThanVaultBalance()
        external
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenCallerIsAuthorized
        whenTokenToSweepIsNotLockToken
        whenAmountToSweepIsNotZero__
        givenVaultBalanceIsNotZero
    {
        uint256 vaultBalance = IERC20(tokenToSweep).balanceOf(vault);

        // It should sweep amount to recipient
        // It should emit a {Sweep} event
        amountToSweep = vaultBalance / 4;
        vm.expectEmit(address(govNFT));
        emit IGovNFT.Sweep({tokenId: tokenId, token: tokenToSweep, recipient: sweepRecipient, amount: amountToSweep});
        govNFT.sweep({_tokenId: tokenId, _token: tokenToSweep, _recipient: sweepRecipient, _amount: amountToSweep});

        assertEq(IERC20(tokenToSweep).balanceOf(vault), vaultBalance - amountToSweep);
        assertEq(IERC20(tokenToSweep).balanceOf(sweepRecipient), amountToSweep);
        assertEq(IERC20(tokenToSweep).balanceOf(address(govNFT)), 0);
    }

    function test_GivenAmountIsEqualOrGreaterThanVaultBalance()
        external
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenCallerIsAuthorized
        whenTokenToSweepIsNotLockToken
        whenAmountToSweepIsNotZero__
        givenVaultBalanceIsNotZero
    {
        uint256 vaultBalance = IERC20(tokenToSweep).balanceOf(vault);

        // It should sweep vault balance to recipient
        // It should emit a {Sweep} event
        amountToSweep = vaultBalance + TOKEN_10K;
        vm.expectEmit(address(govNFT));
        emit IGovNFT.Sweep({tokenId: tokenId, token: tokenToSweep, recipient: sweepRecipient, amount: vaultBalance});
        govNFT.sweep({_tokenId: tokenId, _token: tokenToSweep, _recipient: sweepRecipient, _amount: amountToSweep});

        assertEq(IERC20(tokenToSweep).balanceOf(vault), 0);
        assertEq(IERC20(tokenToSweep).balanceOf(address(govNFT)), 0);
        assertEq(IERC20(tokenToSweep).balanceOf(sweepRecipient), vaultBalance);
    }
}
