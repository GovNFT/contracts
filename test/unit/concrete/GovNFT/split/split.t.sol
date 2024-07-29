// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract SplitUnitConcreteTest is BaseTest {
    uint256 public from;
    IGovNFT.Lock public parentLock;
    IGovNFT.SplitParams[] public paramsList;

    function _setUp() public override {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        from = govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_100K,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 4,
            _cliffLength: WEEK,
            _description: ""
        });
        parentLock = govNFT.locks(from);

        // skip some time so that parentLock's start is in past
        skip(WEEK / 2);
    }

    function test_WhenCallerIsNotAuthorized() external {
        // It should revert with ERC721InsufficientApproval
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(this), from));
        govNFT.split({_from: from, _paramsList: paramsList});
    }

    modifier whenCallerIsAuthorized() {
        vm.startPrank(address(recipient));
        _;
    }

    function test_WhenSplitParamatersListLengthIsZero() external whenCallerIsAuthorized {
        // It should revert with InvalidParamaters
        vm.expectRevert(IGovNFT.InvalidParameters.selector);
        govNFT.split({_from: from, _paramsList: paramsList});
    }

    modifier whenSplitParamatersListLengthIsNotZero() {
        IGovNFT.SplitParams memory params = IGovNFT.SplitParams({
            beneficiary: address(0),
            start: 0,
            end: 0,
            cliff: 0,
            amount: 0,
            description: ""
        });
        paramsList.push(params);
        _;
    }

    function test_WhenOneOfRecipientsIsAddressZero()
        external
        whenCallerIsAuthorized
        whenSplitParamatersListLengthIsNotZero
    {
        // It should revert with ZeroAddress
        vm.expectRevert(IGovNFT.ZeroAddress.selector);
        govNFT.split({_from: from, _paramsList: paramsList});
    }

    modifier whenNoneOfRecipientsIsAddressZero() {
        paramsList[0].beneficiary = address(recipient2);
        _;
    }

    function test_WhenOneOfAmountsIsZero()
        external
        whenCallerIsAuthorized
        whenSplitParamatersListLengthIsNotZero
        whenNoneOfRecipientsIsAddressZero
    {
        // It should revert with ZeroAmount
        vm.expectRevert(IGovNFT.ZeroAmount.selector);
        govNFT.split({_from: from, _paramsList: paramsList});
    }

    modifier whenNoneOfAmountsIsZero() {
        paramsList[0].amount = type(uint256).max;
        _;
    }

    function test_WhenOneOfEndTimesIsEqualToStartTime()
        external
        whenCallerIsAuthorized
        whenSplitParamatersListLengthIsNotZero
        whenNoneOfRecipientsIsAddressZero
        whenNoneOfAmountsIsZero
    {
        // It should revert with InvalidParameters
        vm.expectRevert(IGovNFT.InvalidParameters.selector);
        govNFT.split({_from: from, _paramsList: paramsList});
    }

    modifier whenNoneOfEndTimesIsEqualToStartTime() {
        _;
    }

    function test_WhenOneOfEndTimesIsSmallerThanStartTime()
        external
        whenCallerIsAuthorized
        whenSplitParamatersListLengthIsNotZero
        whenNoneOfRecipientsIsAddressZero
        whenNoneOfAmountsIsZero
        whenNoneOfEndTimesIsEqualToStartTime
    {
        // It should revert with ArithmeticError
        paramsList[0].start = paramsList[0].end + 1;
        vm.expectRevert(stdError.arithmeticError);
        govNFT.split({_from: from, _paramsList: paramsList});
    }

    modifier whenAllEndTimesAreGreaterThanStartTime() {
        paramsList[0].end = paramsList[0].start + 2;
        _;
    }

    function test_WhenOneOfCliffsIsGreaterThanDuration()
        external
        whenCallerIsAuthorized
        whenSplitParamatersListLengthIsNotZero
        whenNoneOfRecipientsIsAddressZero
        whenNoneOfAmountsIsZero
        whenNoneOfEndTimesIsEqualToStartTime
        whenAllEndTimesAreGreaterThanStartTime
    {
        // It should revert with InvalidCliff
        uint40 duration = paramsList[0].end - paramsList[0].start;
        paramsList[0].cliff = duration + 1;
        vm.expectRevert(IGovNFT.InvalidCliff.selector);
        govNFT.split({_from: from, _paramsList: paramsList});
    }

    modifier whenAllCliffsAreEqualOrSmallerThanDuration() {
        uint40 duration = paramsList[0].end - paramsList[0].start;
        paramsList[0].cliff = duration - 1;
        _;
    }

    function test_WhenOneOfEndTimesIsSmallerThanParentLocksEndTime()
        external
        whenCallerIsAuthorized
        whenSplitParamatersListLengthIsNotZero
        whenNoneOfRecipientsIsAddressZero
        whenNoneOfAmountsIsZero
        whenNoneOfEndTimesIsEqualToStartTime
        whenAllEndTimesAreGreaterThanStartTime
        whenAllCliffsAreEqualOrSmallerThanDuration
    {
        assertLt(paramsList[0].end, parentLock.end);
        // It should revert with InvalidEnd
        vm.expectRevert(IGovNFT.InvalidEnd.selector);
        govNFT.split({_from: from, _paramsList: paramsList});
    }

    modifier whenAllEndTimesAreEqualOrGreaterThanParentLocksEndTime() {
        paramsList[0].end = parentLock.end;
        _;
    }

    function test_WhenOneOfStartTimesIsSmallerThanParentLocksStartTime()
        external
        whenCallerIsAuthorized
        whenSplitParamatersListLengthIsNotZero
        whenNoneOfRecipientsIsAddressZero
        whenNoneOfAmountsIsZero
        whenNoneOfEndTimesIsEqualToStartTime
        whenAllEndTimesAreGreaterThanStartTime
        whenAllCliffsAreEqualOrSmallerThanDuration
        whenAllEndTimesAreEqualOrGreaterThanParentLocksEndTime
    {
        assertLt(paramsList[0].start, parentLock.start);
        // It should revert with InvalidStart
        vm.expectRevert(IGovNFT.InvalidStart.selector);
        govNFT.split({_from: from, _paramsList: paramsList});
    }

    modifier whenAllStartTimesAreEqualOrGreaterThanParentLocksStartTime() {
        paramsList[0].start = parentLock.start;
        _;
    }

    function test_WhenOneOfStartTimesIsSmallerThanBlockTimestamp()
        external
        whenCallerIsAuthorized
        whenSplitParamatersListLengthIsNotZero
        whenNoneOfRecipientsIsAddressZero
        whenNoneOfAmountsIsZero
        whenNoneOfEndTimesIsEqualToStartTime
        whenAllEndTimesAreGreaterThanStartTime
        whenAllCliffsAreEqualOrSmallerThanDuration
        whenAllEndTimesAreEqualOrGreaterThanParentLocksEndTime
        whenAllStartTimesAreEqualOrGreaterThanParentLocksStartTime
    {
        assertLt(paramsList[0].start, block.timestamp);
        // It should revert with InvalidStart
        vm.expectRevert(IGovNFT.InvalidStart.selector);
        govNFT.split({_from: from, _paramsList: paramsList});
    }

    modifier whenAllStartTimesAreEqualOrGreaterThanBlockTimestamp() {
        paramsList[0].start = uint40(block.timestamp);
        _;
    }

    function test_WhenOneOfCliffEndsIsSmallerThanParentLocksCliffEnd()
        external
        whenCallerIsAuthorized
        whenSplitParamatersListLengthIsNotZero
        whenNoneOfRecipientsIsAddressZero
        whenNoneOfAmountsIsZero
        whenNoneOfEndTimesIsEqualToStartTime
        whenAllEndTimesAreGreaterThanStartTime
        whenAllCliffsAreEqualOrSmallerThanDuration
        whenAllEndTimesAreEqualOrGreaterThanParentLocksEndTime
        whenAllStartTimesAreEqualOrGreaterThanParentLocksStartTime
        whenAllStartTimesAreEqualOrGreaterThanBlockTimestamp
    {
        uint40 parentCliffEnd = parentLock.start + parentLock.cliffLength;
        uint40 splitCliffEnd = paramsList[0].start + paramsList[0].cliff;
        assertLt(splitCliffEnd, parentCliffEnd);
        // It should revert with InvalidCliff
        vm.expectRevert(IGovNFT.InvalidCliff.selector);
        govNFT.split({_from: from, _paramsList: paramsList});
    }

    modifier whenAllCliffEndsAreEqualOrGreaterThanParentLocksCliffEnd() {
        uint40 parentCliffEnd = parentLock.start + parentLock.cliffLength;
        paramsList[0].cliff = uint40(parentCliffEnd - block.timestamp);
        _;
    }

    function test_WhenSumOfAllSplitAmountsIsGreaterThanCurrentParentLockedAmount()
        external
        whenCallerIsAuthorized
        whenSplitParamatersListLengthIsNotZero
        whenNoneOfRecipientsIsAddressZero
        whenNoneOfAmountsIsZero
        whenNoneOfEndTimesIsEqualToStartTime
        whenAllEndTimesAreGreaterThanStartTime
        whenAllCliffsAreEqualOrSmallerThanDuration
        whenAllEndTimesAreEqualOrGreaterThanParentLocksEndTime
        whenAllStartTimesAreEqualOrGreaterThanParentLocksStartTime
        whenAllStartTimesAreEqualOrGreaterThanBlockTimestamp
        whenAllCliffEndsAreEqualOrGreaterThanParentLocksCliffEnd
    {
        assertGt(paramsList[0].amount, govNFT.locked(from));
        // It should revert with AmountTooBig
        vm.expectRevert(IGovNFT.AmountTooBig.selector);
        govNFT.split({_from: from, _paramsList: paramsList});
    }

    modifier whenSumOfAllSplitAmountsIsEqualOrSmallerThanCurrentParentLockedAmount() {
        paramsList[0].amount = govNFT.locked(from) / 3;
        _;
    }

    function test_GivenVaultBalanceAfterTransferIsSmallerThanAmount()
        external
        whenCallerIsAuthorized
        whenSplitParamatersListLengthIsNotZero
        whenNoneOfRecipientsIsAddressZero
        whenNoneOfAmountsIsZero
        whenNoneOfEndTimesIsEqualToStartTime
        whenAllEndTimesAreGreaterThanStartTime
        whenAllCliffsAreEqualOrSmallerThanDuration
        whenAllEndTimesAreEqualOrGreaterThanParentLocksEndTime
        whenAllStartTimesAreEqualOrGreaterThanParentLocksStartTime
        whenAllStartTimesAreEqualOrGreaterThanBlockTimestamp
        whenAllCliffEndsAreEqualOrGreaterThanParentLocksCliffEnd
        whenSumOfAllSplitAmountsIsEqualOrSmallerThanCurrentParentLockedAmount
    {
        // deploy mock erc-20 with fees, that does not transfer all tokens to recipient
        address feeToken = address(new MockFeeERC20("TEST", "TEST", 18));
        MockFeeERC20(feeToken).setFeeWhitelist(address(govNFT), true);
        deal(feeToken, address(admin), parentLock.totalLocked);
        admin.approve(feeToken, address(govNFT), parentLock.totalLocked);
        vm.startPrank(address(admin));
        from = govNFT.createLock({
            _token: feeToken,
            _recipient: address(recipient),
            _amount: parentLock.totalLocked,
            _startTime: parentLock.start,
            _endTime: parentLock.end,
            _cliffLength: parentLock.cliffLength,
            _description: ""
        });

        // It should revert with InsufficientAmount
        vm.startPrank(address(recipient));
        vm.expectRevert(IGovNFT.InsufficientAmount.selector);
        govNFT.split({_from: from, _paramsList: paramsList});
    }

    modifier givenVaultBalanceIsEqualOrGreaterThanAmount() {
        _;
    }

    function test_GivenBlockTimestampIsSmallerThanParentLockCliffEnd()
        external
        whenCallerIsAuthorized
        whenSplitParamatersListLengthIsNotZero
        whenNoneOfRecipientsIsAddressZero
        whenNoneOfAmountsIsZero
        whenNoneOfEndTimesIsEqualToStartTime
        whenAllEndTimesAreGreaterThanStartTime
        whenAllCliffsAreEqualOrSmallerThanDuration
        whenAllEndTimesAreEqualOrGreaterThanParentLocksEndTime
        whenAllStartTimesAreEqualOrGreaterThanParentLocksStartTime
        whenAllStartTimesAreEqualOrGreaterThanBlockTimestamp
        whenAllCliffEndsAreEqualOrGreaterThanParentLocksCliffEnd
        whenSumOfAllSplitAmountsIsEqualOrSmallerThanCurrentParentLockedAmount
        givenVaultBalanceIsEqualOrGreaterThanAmount
    {
        IGovNFT.SplitParams memory params = paramsList[0];
        vm.expectEmit(address(govNFT));
        // It should emit a {Split} event
        emit IGovNFT.Split({
            from: from,
            to: from + 1,
            recipient: params.beneficiary,
            splitAmount1: parentLock.totalLocked - params.amount,
            splitAmount2: params.amount,
            startTime: params.start,
            endTime: params.end,
            description: ""
        });
        // It should emit a {MetadataUpdate} event
        vm.expectEmit(address(govNFT));
        emit IERC4906.MetadataUpdate(from);

        uint256 splitId = govNFT.split({_from: from, _paramsList: paramsList})[0];
        IGovNFT.Lock memory splitLock = govNFT.locks(splitId);

        // It should mint an NFT for each set of Split parameters
        assertEq(govNFT.tokenId(), from + 1);
        // It should set totalLocked to _param.amount in split NFTs
        assertEq(splitLock.totalLocked, params.amount);
        // It should set initialDeposit to _param.amount in split NFTs
        assertEq(splitLock.initialDeposit, params.amount);
        // It should set totalClaimed to zero in split NFTs
        assertEq(splitLock.totalClaimed, 0);
        // It should set unclaimedBeforeSplit to zero in split NFTs
        assertEq(splitLock.unclaimedBeforeSplit, 0);
        // It should set splitCount to zero in split NFTs
        assertEq(splitLock.unclaimedBeforeSplit, 0);
        // It should set cliffLength to _param.cliff in split NFTs
        assertEq(splitLock.cliffLength, params.cliff);
        // It should set start to _param.start in split NFTs
        assertEq(splitLock.start, params.start);
        // It should set end to _param.end in split NFTs
        assertEq(splitLock.end, params.end);
        // It should set token to parent lock token in split NFTs
        assertEq(splitLock.token, parentLock.token);
        // It should set vault to a new vault in split NFTs
        assertNotEq(splitLock.vault, address(0));
        assertEq(IVault(splitLock.vault).owner(), address(govNFT));
        assertEq(IVault(splitLock.vault).token(), parentLock.token);
        // It should set minter to msg.sender in split NFTs
        assertEq(splitLock.minter, address(recipient));
        // It should add splitNFTs to parent's splitTokensByIndex
        assertEq(govNFT.splitTokensByIndex(from, 0), splitId);
        // It should add number of new split NFTs to parent's splitCount
        assertEq(govNFT.locks(from).splitCount, parentLock.splitCount + 1);
        // It should subtract sum of amounts from totalLocked in parent lock
        assertEq(govNFT.locks(from).totalLocked, parentLock.totalLocked - params.amount);
        // It should keep unclaimedBeforeSplit in parent lock set to 0
        assertEq(govNFT.locks(from).unclaimedBeforeSplit, 0);
        // It should delete parent lock total claimed
        assertEq(govNFT.locks(from).totalClaimed, 0);
    }

    function test_GivenBlockTimestampIsGreaterOrEqualToParentLockCliffEnd()
        external
        whenCallerIsAuthorized
        whenSplitParamatersListLengthIsNotZero
        whenNoneOfRecipientsIsAddressZero
        whenNoneOfAmountsIsZero
        whenNoneOfEndTimesIsEqualToStartTime
        whenAllEndTimesAreGreaterThanStartTime
        whenAllCliffsAreEqualOrSmallerThanDuration
        whenAllEndTimesAreEqualOrGreaterThanParentLocksEndTime
        whenAllStartTimesAreEqualOrGreaterThanParentLocksStartTime
        whenAllStartTimesAreEqualOrGreaterThanBlockTimestamp
        whenAllCliffEndsAreEqualOrGreaterThanParentLocksCliffEnd
        whenSumOfAllSplitAmountsIsEqualOrSmallerThanCurrentParentLockedAmount
        givenVaultBalanceIsEqualOrGreaterThanAmount
    {
        vm.warp(parentLock.start + parentLock.cliffLength + WEEK);
        paramsList[0].start = uint40(block.timestamp);

        uint256 oldLocked = govNFT.locked(from);
        uint256 oldUnclaimed = govNFT.unclaimed(from);

        IGovNFT.SplitParams memory params = paramsList[0];
        vm.expectEmit(address(govNFT));
        // It should emit a {Split} event
        emit IGovNFT.Split({
            from: from,
            to: from + 1,
            recipient: params.beneficiary,
            splitAmount1: oldLocked - params.amount,
            splitAmount2: params.amount,
            startTime: params.start,
            endTime: params.end,
            description: ""
        });
        // It should emit a {MetadataUpdate} event
        vm.expectEmit(address(govNFT));
        emit IERC4906.MetadataUpdate(from);

        uint256 splitId = govNFT.split({_from: from, _paramsList: paramsList})[0];
        IGovNFT.Lock memory splitLock = govNFT.locks(splitId);

        // It should mint an NFT for each set of Split parameters
        assertEq(govNFT.tokenId(), from + 1);
        // It should set totalLocked to _param.amount in split NFTs
        assertEq(splitLock.totalLocked, params.amount);
        // It should set initialDeposit to _param.amount in split NFTs
        assertEq(splitLock.initialDeposit, params.amount);
        // It should set totalClaimed to zero in split NFTs
        assertEq(splitLock.totalClaimed, 0);
        // It should set unclaimedBeforeSplit to zero in split NFTs
        assertEq(splitLock.unclaimedBeforeSplit, 0);
        // It should set splitCount to zero in split NFTs
        assertEq(splitLock.unclaimedBeforeSplit, 0);
        // It should set cliffLength to _param.cliff in split NFTs
        assertEq(splitLock.cliffLength, params.cliff);
        // It should set start to _param.start in split NFTs
        assertEq(splitLock.start, params.start);
        // It should set end to _param.end in split NFTs
        assertEq(splitLock.end, params.end);
        // It should set token to parent lock token in split NFTs
        assertEq(splitLock.token, parentLock.token);
        // It should set vault to a new vault in split NFTs
        assertNotEq(splitLock.vault, address(0));
        assertEq(IVault(splitLock.vault).owner(), address(govNFT));
        assertEq(IVault(splitLock.vault).token(), parentLock.token);
        // It should set minter to msg.sender in split NFTs
        assertEq(splitLock.minter, address(recipient));
        // It should add splitNFTs to parent's splitTokensByIndex
        assertEq(govNFT.splitTokensByIndex(from, 0), splitId);
        // It should add number of new split NFTs to parent's splitCount
        assertEq(govNFT.locks(from).splitCount, parentLock.splitCount + 1);
        // It should subtract sum of amounts from totalLocked in parent lock
        assertEq(govNFT.locks(from).totalLocked, oldLocked - params.amount);
        // It should set start to block timestamp in parent lock
        assertEq(govNFT.locks(from).start, block.timestamp);
        // It should delete parent lock cliff
        assertEq(govNFT.locks(from).cliffLength, 0);
        // It should add total unclaimed to parent lock unclaimedBeforeSplit
        assertEq(govNFT.locks(from).unclaimedBeforeSplit, oldUnclaimed);
        // It should delete parent lock total claimed
        assertEq(govNFT.locks(from).totalClaimed, 0);
    }
}
