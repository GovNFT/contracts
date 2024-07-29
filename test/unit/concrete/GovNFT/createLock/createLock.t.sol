// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract CreateLockUnitConcreteTest is BaseTest {
    GovNFT public permissionlessGovNFT;
    GovNFT public permissionedGovNFT;
    address public token;
    uint256 public amount;
    uint40 public endTime;
    uint40 public startTime;
    uint40 public cliffLength;
    address public lockRecipient;
    address public feeOnTransferToken;

    function _setUp() public override {
        permissionedGovNFT = govNFT;
        permissionlessGovNFT = GovNFT(factory.govNFT());
        // deploy mock erc-20 with fees, that does not transfer all tokens to recipient
        feeOnTransferToken = address(new MockFeeERC20("TEST", "TEST", 18));
        deal(feeOnTransferToken, address(admin), TOKEN_100K);
    }

    modifier givenGovNFTIsNotPermissionless() {
        govNFT = permissionedGovNFT;
        _;
    }

    function test_WhenCallerIsNotOwner() external givenGovNFTIsNotPermissionless {
        // It should revert with OwnableUnauthorizedAccount
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        govNFT.createLock({
            _token: testToken,
            _recipient: lockRecipient,
            _amount: amount,
            _startTime: startTime,
            _endTime: endTime,
            _cliffLength: cliffLength,
            _description: ""
        });
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(address(admin));
        assertEq(address(admin), Ownable(govNFT).owner());
        _;
    }

    function test_WhenTokenIsAddressZero_() external givenGovNFTIsNotPermissionless whenCallerIsOwner {
        // It should revert with ZeroAddress
        vm.expectRevert(IGovNFT.ZeroAddress.selector);
        govNFT.createLock({
            _token: token,
            _recipient: lockRecipient,
            _amount: amount,
            _startTime: startTime,
            _endTime: endTime,
            _cliffLength: cliffLength,
            _description: ""
        });
    }

    modifier whenTokenIsNotAddressZero_() {
        token = testToken;
        assertNotEq(token, address(0));
        _;
    }

    function test_WhenRecipientIsAddressZero_()
        external
        givenGovNFTIsNotPermissionless
        whenCallerIsOwner
        whenTokenIsNotAddressZero_
    {
        // It should revert with ZeroAddress
        vm.expectRevert(IGovNFT.ZeroAddress.selector);
        govNFT.createLock({
            _token: token,
            _recipient: lockRecipient,
            _amount: amount,
            _startTime: startTime,
            _endTime: endTime,
            _cliffLength: cliffLength,
            _description: ""
        });
    }

    modifier whenRecipientIsNotAddressZero_() {
        lockRecipient = address(recipient);
        assertNotEq(lockRecipient, address(0));
        _;
    }

    function test_WhenAmountIsZero_()
        external
        givenGovNFTIsNotPermissionless
        whenCallerIsOwner
        whenTokenIsNotAddressZero_
        whenRecipientIsNotAddressZero_
    {
        // It should revert with ZeroAmount
        vm.expectRevert(IGovNFT.ZeroAmount.selector);
        govNFT.createLock({
            _token: token,
            _recipient: lockRecipient,
            _amount: amount,
            _startTime: startTime,
            _endTime: endTime,
            _cliffLength: cliffLength,
            _description: ""
        });
    }

    modifier whenAmountIsNotZero_() {
        amount = TOKEN_100K;
        assertGt(amount, 0);
        _;
    }

    function test_WhenEndTimeIsEqualToStartTime_()
        external
        givenGovNFTIsNotPermissionless
        whenCallerIsOwner
        whenTokenIsNotAddressZero_
        whenRecipientIsNotAddressZero_
        whenAmountIsNotZero_
    {
        // It should revert with InvalidParameters
        vm.expectRevert(IGovNFT.InvalidParameters.selector);
        govNFT.createLock({
            _token: token,
            _recipient: lockRecipient,
            _amount: amount,
            _startTime: startTime,
            _endTime: endTime,
            _cliffLength: cliffLength,
            _description: ""
        });
    }

    modifier whenEndTimeDoesNotEqualStartTime_() {
        startTime = uint40(block.timestamp);
        endTime = startTime + WEEK * 2;
        assertNotEq(startTime, endTime);
        _;
    }

    function test_WhenEndTimeIsSmallerThanStartTime_()
        external
        givenGovNFTIsNotPermissionless
        whenCallerIsOwner
        whenTokenIsNotAddressZero_
        whenRecipientIsNotAddressZero_
        whenAmountIsNotZero_
        whenEndTimeDoesNotEqualStartTime_
    {
        startTime = uint40(block.timestamp) + WEEK;
        endTime = uint40(block.timestamp);
        assertLt(endTime, startTime);

        // It should revert with ArithmeticError
        vm.expectRevert(stdError.arithmeticError);
        govNFT.createLock({
            _token: token,
            _recipient: lockRecipient,
            _amount: amount,
            _startTime: startTime,
            _endTime: endTime,
            _cliffLength: cliffLength,
            _description: ""
        });
    }

    modifier whenEndTimeIsGreaterThanStartTime_() {
        startTime = uint40(block.timestamp);
        endTime = startTime + WEEK * 2;
        assertGt(endTime, startTime);
        _;
    }

    function test_WhenCliffIsGreaterThanDuration_()
        external
        givenGovNFTIsNotPermissionless
        whenCallerIsOwner
        whenTokenIsNotAddressZero_
        whenRecipientIsNotAddressZero_
        whenAmountIsNotZero_
        whenEndTimeDoesNotEqualStartTime_
        whenEndTimeIsGreaterThanStartTime_
    {
        cliffLength = WEEK * 2 + 1;
        assertGt(cliffLength, endTime - startTime);
        // It should revert with InvalidCliff
        vm.expectRevert(IGovNFT.InvalidCliff.selector);
        govNFT.createLock({
            _token: token,
            _recipient: lockRecipient,
            _amount: amount,
            _startTime: startTime,
            _endTime: endTime,
            _cliffLength: cliffLength,
            _description: ""
        });
    }

    modifier whenCliffIsEqualOrSmallerThanDuration_() {
        cliffLength = WEEK;
        assertLt(cliffLength, endTime - startTime);
        _;
    }

    function test_GivenVaultBalanceAfterTransferIsSmallerThanAmount_()
        external
        givenGovNFTIsNotPermissionless
        whenCallerIsOwner
        whenTokenIsNotAddressZero_
        whenRecipientIsNotAddressZero_
        whenAmountIsNotZero_
        whenEndTimeDoesNotEqualStartTime_
        whenEndTimeIsGreaterThanStartTime_
        whenCliffIsEqualOrSmallerThanDuration_
    {
        admin.approve(feeOnTransferToken, address(govNFT), amount);
        // It should revert with InsufficientAmount
        vm.expectRevert(IGovNFT.InsufficientAmount.selector);
        govNFT.createLock({
            _token: feeOnTransferToken,
            _recipient: lockRecipient,
            _amount: amount,
            _startTime: startTime,
            _endTime: endTime,
            _cliffLength: cliffLength,
            _description: ""
        });
    }

    function test_GivenVaultBalanceIsEqualOrGreaterThanAmount_()
        external
        givenGovNFTIsNotPermissionless
        whenCallerIsOwner
        whenTokenIsNotAddressZero_
        whenRecipientIsNotAddressZero_
        whenAmountIsNotZero_
        whenEndTimeDoesNotEqualStartTime_
        whenEndTimeIsGreaterThanStartTime_
        whenCliffIsEqualOrSmallerThanDuration_
    {
        uint256 tokenIdBefore = govNFT.tokenId();
        admin.approve(token, address(govNFT), amount);

        // It should emit a {Create} event
        vm.expectEmit(address(govNFT));
        emit IGovNFT.Create(tokenIdBefore + 1, address(recipient), token, amount, "");
        uint256 tokenId = govNFT.createLock({
            _token: token,
            _recipient: lockRecipient,
            _amount: amount,
            _startTime: startTime,
            _endTime: endTime,
            _cliffLength: cliffLength,
            _description: ""
        });

        IGovNFT.Lock memory lock = govNFT.locks(tokenId);

        // It should create a vault
        // It should set vault to new vault in new lock
        assertNotEq(lock.vault, address(0));
        // It should increment _tokenId
        assertEq(tokenId, tokenIdBefore + 1);
        // It should mint an NFT with _tokenId to recipient
        assertEq(govNFT.ownerOf(tokenId), address(recipient));
        // It should set totalLocked to amount in new lock
        assertEq(lock.totalLocked, amount);
        // It should set initialDeposit to amount in new lock
        assertEq(lock.initialDeposit, amount);
        // It should set totalClaimed to zero in new lock
        assertEq(lock.totalClaimed, 0);
        // It should set unclaimedBeforeSplit to zero in new lock
        assertEq(lock.unclaimedBeforeSplit, 0);
        // It should set token to _token in new lock
        assertEq(lock.token, token);
        // It should set splitCount to zero in new lock
        assertEq(lock.splitCount, 0);
        // It should set cliffLength to _cliffLength in new lock
        assertEq(lock.cliffLength, cliffLength);
        // It should set start to _startTime in new lock
        assertEq(lock.start, startTime);
        // It should set end to _endTime in new lock
        assertEq(lock.end, endTime);
        // It should set minter to msg.sender in new lock
        assertEq(lock.minter, address(admin));
        // It should send amount to vault
        assertEq(IERC20(token).balanceOf(lock.vault), amount);

        IVault vault = IVault(lock.vault);
        assertEq(vault.token(), token);
        assertEq(vault.owner(), address(govNFT));
    }

    modifier givenGovNFTIsPermissionless() {
        govNFT = permissionlessGovNFT;
        _;
    }

    function test_WhenTokenIsAddressZero() external givenGovNFTIsPermissionless {
        // It should revert with ZeroAddress
        vm.expectRevert(IGovNFT.ZeroAddress.selector);
        govNFT.createLock({
            _token: token,
            _recipient: lockRecipient,
            _amount: amount,
            _startTime: startTime,
            _endTime: endTime,
            _cliffLength: cliffLength,
            _description: ""
        });
    }

    modifier whenTokenIsNotAddressZero() {
        token = testToken;
        assertNotEq(token, address(0));
        _;
    }

    function test_WhenRecipientIsAddressZero() external givenGovNFTIsPermissionless whenTokenIsNotAddressZero {
        // It should revert with ZeroAddress
        vm.expectRevert(IGovNFT.ZeroAddress.selector);
        govNFT.createLock({
            _token: token,
            _recipient: lockRecipient,
            _amount: amount,
            _startTime: startTime,
            _endTime: endTime,
            _cliffLength: cliffLength,
            _description: ""
        });
    }

    modifier whenRecipientIsNotAddressZero() {
        lockRecipient = address(recipient);
        assertNotEq(lockRecipient, address(0));
        _;
    }

    function test_WhenAmountIsZero()
        external
        givenGovNFTIsPermissionless
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
    {
        // It should revert with ZeroAmount
        vm.expectRevert(IGovNFT.ZeroAmount.selector);
        govNFT.createLock({
            _token: token,
            _recipient: lockRecipient,
            _amount: amount,
            _startTime: startTime,
            _endTime: endTime,
            _cliffLength: cliffLength,
            _description: ""
        });
    }

    modifier whenAmountIsNotZero() {
        amount = TOKEN_100K;
        assertGt(amount, 0);
        _;
    }

    function test_WhenEndTimeIsEqualToStartTime()
        external
        givenGovNFTIsPermissionless
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenAmountIsNotZero
    {
        // It should revert with InvalidParameters
        vm.expectRevert(IGovNFT.InvalidParameters.selector);
        govNFT.createLock({
            _token: token,
            _recipient: lockRecipient,
            _amount: amount,
            _startTime: startTime,
            _endTime: endTime,
            _cliffLength: cliffLength,
            _description: ""
        });
    }

    modifier whenEndTimeDoesNotEqualStartTime() {
        startTime = uint40(block.timestamp);
        endTime = startTime + WEEK * 2;
        assertNotEq(startTime, endTime);
        _;
    }

    function test_WhenEndTimeIsSmallerThanStartTime()
        external
        givenGovNFTIsPermissionless
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenAmountIsNotZero
        whenEndTimeDoesNotEqualStartTime
    {
        startTime = uint40(block.timestamp) + WEEK;
        endTime = uint40(block.timestamp);
        assertLt(endTime, startTime);

        // It should revert with ArithmeticError
        vm.expectRevert(stdError.arithmeticError);
        govNFT.createLock({
            _token: token,
            _recipient: lockRecipient,
            _amount: amount,
            _startTime: startTime,
            _endTime: endTime,
            _cliffLength: cliffLength,
            _description: ""
        });
    }

    modifier whenEndTimeIsGreaterThanStartTime() {
        startTime = uint40(block.timestamp);
        endTime = startTime + WEEK * 2;
        assertGt(endTime, startTime);
        _;
    }

    function test_WhenCliffIsGreaterThanDuration()
        external
        givenGovNFTIsPermissionless
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenAmountIsNotZero
        whenEndTimeDoesNotEqualStartTime
        whenEndTimeIsGreaterThanStartTime
    {
        cliffLength = WEEK * 2 + 1;
        assertGt(cliffLength, endTime - startTime);
        // It should revert with InvalidCliff
        vm.expectRevert(IGovNFT.InvalidCliff.selector);
        govNFT.createLock({
            _token: token,
            _recipient: lockRecipient,
            _amount: amount,
            _startTime: startTime,
            _endTime: endTime,
            _cliffLength: cliffLength,
            _description: ""
        });
    }

    modifier whenCliffIsEqualOrSmallerThanDuration() {
        cliffLength = WEEK;
        assertLt(cliffLength, endTime - startTime);
        _;
    }

    function test_GivenVaultBalanceAfterTransferIsSmallerThanAmount()
        external
        givenGovNFTIsPermissionless
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenAmountIsNotZero
        whenEndTimeDoesNotEqualStartTime
        whenEndTimeIsGreaterThanStartTime
        whenCliffIsEqualOrSmallerThanDuration
    {
        admin.approve(feeOnTransferToken, address(govNFT), amount);
        vm.startPrank(address(admin));
        // It should revert with InsufficientAmount
        vm.expectRevert(IGovNFT.InsufficientAmount.selector);
        govNFT.createLock({
            _token: feeOnTransferToken,
            _recipient: lockRecipient,
            _amount: amount,
            _startTime: startTime,
            _endTime: endTime,
            _cliffLength: cliffLength,
            _description: ""
        });
    }

    function test_GivenVaultBalanceIsEqualOrGreaterThanAmount()
        external
        givenGovNFTIsPermissionless
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenAmountIsNotZero
        whenEndTimeDoesNotEqualStartTime
        whenEndTimeIsGreaterThanStartTime
        whenCliffIsEqualOrSmallerThanDuration
    {
        uint256 tokenIdBefore = govNFT.tokenId();
        admin.approve(token, address(govNFT), amount);
        vm.startPrank(address(admin));

        // It should emit a {Create} event
        vm.expectEmit(address(govNFT));
        emit IGovNFT.Create(tokenIdBefore + 1, address(recipient), token, amount, "");
        uint256 tokenId = govNFT.createLock({
            _token: token,
            _recipient: lockRecipient,
            _amount: amount,
            _startTime: startTime,
            _endTime: endTime,
            _cliffLength: cliffLength,
            _description: ""
        });

        IGovNFT.Lock memory lock = govNFT.locks(tokenId);

        // It should create a vault
        // It should set vault to new vault in new lock
        assertNotEq(lock.vault, address(0));
        // It should increment _tokenId
        assertEq(tokenId, tokenIdBefore + 1);
        // It should mint an NFT with _tokenId to recipient
        assertEq(govNFT.ownerOf(tokenId), address(recipient));
        // It should set totalLocked to amount in new lock
        assertEq(lock.totalLocked, amount);
        // It should set initialDeposit to amount in new lock
        assertEq(lock.initialDeposit, amount);
        // It should set totalClaimed to zero in new lock
        assertEq(lock.totalClaimed, 0);
        // It should set unclaimedBeforeSplit to zero in new lock
        assertEq(lock.unclaimedBeforeSplit, 0);
        // It should set token to _token in new lock
        assertEq(lock.token, token);
        // It should set splitCount to zero in new lock
        assertEq(lock.splitCount, 0);
        // It should set cliffLength to _cliffLength in new lock
        assertEq(lock.cliffLength, cliffLength);
        // It should set start to _startTime in new lock
        assertEq(lock.start, startTime);
        // It should set end to _endTime in new lock
        assertEq(lock.end, endTime);
        // It should set minter to msg.sender in new lock
        assertEq(lock.minter, address(admin));
        // It should send amount to vault
        assertEq(IERC20(token).balanceOf(lock.vault), amount);

        IVault vault = IVault(lock.vault);
        assertEq(vault.token(), token);
        assertEq(vault.owner(), address(govNFT));
    }
}
