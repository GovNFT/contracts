// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract CreateLockUnitFuzzTest is BaseTest {
    GovNFT public permissionlessGovNFT;
    GovNFT public permissionedGovNFT;
    address public token;
    uint256 public amount;
    uint40 public endTime;
    uint40 public startTime;
    uint40 public cliffLength;
    address public feeOnTransferToken;
    address public lockRecipient;

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

    modifier whenCallerIsOwner() {
        vm.startPrank(address(admin));
        assertEq(address(admin), Ownable(govNFT).owner());
        _;
    }

    modifier whenTokenIsNotAddressZero_() {
        token = testToken;
        assertNotEq(token, address(0));
        _;
    }

    modifier whenRecipientIsNotAddressZero_() {
        lockRecipient = address(recipient);
        assertNotEq(lockRecipient, address(0));
        _;
    }

    modifier whenAmountIsNotZero_(uint256 lockAmount) {
        amount = bound(lockAmount, 1, TOKEN_100K);
        assertGt(amount, 0);
        _;
    }

    modifier whenEndTimeDoesNotEqualStartTime_() {
        startTime = uint40(block.timestamp);
        endTime = startTime + WEEK * 2;
        assertNotEq(startTime, endTime);
        _;
    }

    function testFuzz_WhenEndTimeIsSmallerThanStartTime_(
        uint40 start,
        uint40 end
    )
        external
        givenGovNFTIsNotPermissionless
        whenCallerIsOwner
        whenTokenIsNotAddressZero_
        whenRecipientIsNotAddressZero_
        whenAmountIsNotZero_(TOKEN_100K)
        whenEndTimeDoesNotEqualStartTime_
    {
        startTime = uint40(bound(start, 1, type(uint40).max));
        endTime = uint40(bound(end, 0, startTime - 1));
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

    modifier whenEndTimeIsGreaterThanStartTime_(uint40 start, uint40 end) {
        startTime = uint40(bound(start, 0, type(uint40).max - 2));
        endTime = uint40(bound(end, startTime + 1, type(uint40).max - 1));
        assertGt(endTime, startTime);
        _;
    }

    function testFuzz_WhenCliffIsGreaterThanDuration_(
        uint40 start,
        uint40 end,
        uint40 cliff
    )
        external
        givenGovNFTIsNotPermissionless
        whenCallerIsOwner
        whenTokenIsNotAddressZero_
        whenRecipientIsNotAddressZero_
        whenAmountIsNotZero_(TOKEN_100K)
        whenEndTimeDoesNotEqualStartTime_
        whenEndTimeIsGreaterThanStartTime(start, end)
    {
        cliff = uint40(bound(cliff, endTime - startTime + 1, type(uint40).max));
        cliffLength = cliff;

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

    modifier whenCliffIsEqualOrSmallerThanDuration_(uint40 cliff) {
        cliffLength = uint40(bound(cliff, 0, endTime - startTime));
        assertLe(cliffLength, endTime - startTime);
        _;
    }

    function testFuzz_GivenVaultBalanceAfterTransferIsSmallerThanAmount_(
        uint256 lockAmount
    )
        external
        givenGovNFTIsNotPermissionless
        whenCallerIsOwner
        whenTokenIsNotAddressZero_
        whenRecipientIsNotAddressZero_
        whenAmountIsNotZero_(lockAmount)
        whenEndTimeDoesNotEqualStartTime_
        whenEndTimeIsGreaterThanStartTime(uint40(block.timestamp), uint40(block.timestamp) + WEEK * 2)
        whenCliffIsEqualOrSmallerThanDuration_(cliffLength)
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

    function testFuzz_GivenVaultBalanceIsEqualOrGreaterThanAmount_(
        uint40 cliff,
        uint40 start,
        uint40 end,
        uint256 lockAmount
    )
        external
        givenGovNFTIsNotPermissionless
        whenCallerIsOwner
        whenTokenIsNotAddressZero_
        whenRecipientIsNotAddressZero_
        whenAmountIsNotZero_(lockAmount)
        whenEndTimeDoesNotEqualStartTime_
        whenEndTimeIsGreaterThanStartTime(start, end)
        whenCliffIsEqualOrSmallerThanDuration_(cliff)
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

    modifier givenGovNFTIsPermissionless() {
        govNFT = permissionlessGovNFT;
        _;
    }

    modifier whenTokenIsNotAddressZero() {
        token = testToken;
        assertNotEq(token, address(0));
        _;
    }

    modifier whenRecipientIsNotAddressZero() {
        lockRecipient = address(recipient);
        assertNotEq(lockRecipient, address(0));
        _;
    }

    modifier whenAmountIsNotZero(uint256 lockAmount) {
        amount = bound(lockAmount, 1, TOKEN_100K);
        assertGt(amount, 0);
        _;
    }

    modifier whenEndTimeDoesNotEqualStartTime() {
        startTime = uint40(block.timestamp);
        endTime = startTime + WEEK * 2;
        assertNotEq(startTime, endTime);
        _;
    }

    function testFuzz_WhenEndTimeIsSmallerThanStartTime(
        uint40 start,
        uint40 end
    )
        external
        givenGovNFTIsPermissionless
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenAmountIsNotZero(TOKEN_100K)
        whenEndTimeDoesNotEqualStartTime
    {
        startTime = uint40(bound(start, 1, type(uint40).max));
        endTime = uint40(bound(end, 0, startTime - 1));
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

    modifier whenEndTimeIsGreaterThanStartTime(uint40 start, uint40 end) {
        startTime = uint40(bound(start, 0, type(uint40).max - 2));
        endTime = uint40(bound(end, startTime + 1, type(uint40).max - 1));
        assertGt(endTime, startTime);
        _;
    }

    function testFuzz_WhenCliffIsGreaterThanDuration(
        uint40 start,
        uint40 end,
        uint40 cliff
    )
        external
        givenGovNFTIsPermissionless
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenAmountIsNotZero(TOKEN_100K)
        whenEndTimeDoesNotEqualStartTime
        whenEndTimeIsGreaterThanStartTime(start, end)
    {
        cliffLength = uint40(bound(cliff, endTime - startTime + 1, type(uint40).max));
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

    modifier whenCliffIsEqualOrSmallerThanDuration(uint40 cliff, uint40 duration) {
        cliffLength = uint40(bound(cliff, 0, duration));
        assertLe(cliffLength, endTime - startTime);
        _;
    }

    function testFuzz_GivenVaultBalanceAfterTransferIsSmallerThanAmount(
        uint256 lockAmount
    )
        external
        givenGovNFTIsPermissionless
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenAmountIsNotZero(lockAmount)
        whenEndTimeDoesNotEqualStartTime
        whenEndTimeIsGreaterThanStartTime(uint40(block.timestamp), uint40(block.timestamp) + WEEK * 2)
        whenCliffIsEqualOrSmallerThanDuration_(cliffLength)
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

    function testFuzz_GivenVaultBalanceIsEqualOrGreaterThanAmount(
        uint40 cliff,
        uint40 start,
        uint40 end,
        uint256 lockAmount
    )
        external
        givenGovNFTIsPermissionless
        whenTokenIsNotAddressZero
        whenRecipientIsNotAddressZero
        whenAmountIsNotZero(lockAmount)
        whenEndTimeDoesNotEqualStartTime
        whenEndTimeIsGreaterThanStartTime(start, end)
        whenCliffIsEqualOrSmallerThanDuration_(cliff)
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
