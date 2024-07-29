// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract SplitUnitFuzzTest is BaseTest {
    uint256 public from;
    uint256 public constant splitCount = 10;

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

    modifier whenCallerIsAuthorized() {
        vm.startPrank(address(recipient));
        _;
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
        for (uint256 i = 0; i < splitCount; i++) {
            paramsList.push(params);
        }
        assertEq(paramsList.length, splitCount);
        _;
    }

    modifier whenNoneOfRecipientsIsAddressZero() {
        for (uint256 i = 0; i < splitCount; i++) {
            paramsList[i].beneficiary = address(recipient2);
        }
        _;
    }

    modifier whenNoneOfAmountsIsZero() {
        uint256 maxAmount = (type(uint256).max - TOKEN_1) / splitCount;
        for (uint256 i = 0; i < splitCount; i++) {
            paramsList[i].amount = maxAmount;
        }
        _;
    }

    modifier whenNoneOfEndTimesIsEqualToStartTime() {
        _;
    }

    function testFuzz_WhenOneOfEndTimesIsSmallerThanStartTime(
        uint40 start,
        uint40 end
    )
        external
        whenCallerIsAuthorized
        whenSplitParamatersListLengthIsNotZero
        whenNoneOfRecipientsIsAddressZero
        whenNoneOfAmountsIsZero
        whenNoneOfEndTimesIsEqualToStartTime
    {
        // update start to avoid underflows
        paramsList[0].start = uint40(bound(start, 1, type(uint40).max));
        // set invalid end at first index, to avoid InvalidParameters
        paramsList[0].end = uint40(bound(end, 0, paramsList[0].start - 1));

        // It should revert with ArithmeticError
        assertLt(paramsList[0].end, paramsList[0].start);
        vm.expectRevert(stdError.arithmeticError);
        govNFT.split({_from: from, _paramsList: paramsList});
    }

    modifier whenAllEndTimesAreGreaterThanStartTime(uint40 start, uint40 end) {
        for (uint256 i = 0; i < splitCount; i++) {
            // generate different start and end timestamps for each split
            start = uint40(uint256(keccak256(abi.encode(start, i))));
            end = uint40(uint256(keccak256(abi.encode(end, i))));
            paramsList[i].start = uint40(bound(start, 0, type(uint40).max - 1));
            paramsList[i].end = uint40(bound(end, start + 1, type(uint40).max));
        }
        _;
    }

    function testFuzz_WhenOneOfCliffsIsGreaterThanDuration(
        uint40 start,
        uint40 end,
        uint40 cliff
    )
        external
        whenCallerIsAuthorized
        whenSplitParamatersListLengthIsNotZero
        whenNoneOfRecipientsIsAddressZero
        whenNoneOfAmountsIsZero
        whenNoneOfEndTimesIsEqualToStartTime
        whenAllEndTimesAreGreaterThanStartTime(start, end)
    {
        uint256 salt = uint256(keccak256(abi.encodePacked(cliff, splitCount)));
        uint256 randomIndex = bound(salt, 0, splitCount - 1);

        // randomly choose an invalid cliff
        uint40 duration = paramsList[randomIndex].end - paramsList[randomIndex].start;
        paramsList[randomIndex].cliff = uint40(bound(cliff, duration + 1, type(uint40).max));

        // It should revert with InvalidCliff
        vm.expectRevert(IGovNFT.InvalidCliff.selector);
        govNFT.split({_from: from, _paramsList: paramsList});
    }

    modifier whenAllCliffsAreEqualOrSmallerThanDuration(uint40 cliff) {
        for (uint256 i = 0; i < splitCount; i++) {
            // generate different cliff for each split
            cliff = uint40(uint256(keccak256(abi.encode(cliff, i))));
            paramsList[i].cliff = uint40(bound(cliff, 0, paramsList[i].end - paramsList[i].start));
        }
        _;
    }

    function testFuzz_WhenOneOfEndTimesIsSmallerThanParentLocksEndTime(
        uint40 start,
        uint40 end,
        uint40 cliff
    )
        external
        whenCallerIsAuthorized
        whenSplitParamatersListLengthIsNotZero
        whenNoneOfRecipientsIsAddressZero
        whenNoneOfAmountsIsZero
        whenNoneOfEndTimesIsEqualToStartTime
        whenAllEndTimesAreGreaterThanStartTime(start, end)
        whenAllCliffsAreEqualOrSmallerThanDuration(cliff)
    {
        uint256 salt = uint256(keccak256(abi.encodePacked(end, splitCount)));
        uint256 randomIndex = bound(salt, 0, splitCount - 1);

        // update start to avoid underflows and invalidstart
        paramsList[randomIndex].start = uint40(bound(start, block.timestamp, parentLock.end));
        // randomly choose an invalid end
        paramsList[randomIndex].end = uint40(bound(end, paramsList[randomIndex].start + 1, parentLock.end - 1));
        // update cliff to avoid invalidcliff
        paramsList[randomIndex].cliff = uint40(
            bound(cliff, 0, paramsList[randomIndex].end - paramsList[randomIndex].start)
        );

        // It should revert with InvalidEnd
        vm.expectRevert(IGovNFT.InvalidEnd.selector);
        govNFT.split({_from: from, _paramsList: paramsList});
    }

    modifier whenAllEndTimesAreEqualOrGreaterThanParentLocksEndTime(uint40 end) {
        for (uint256 i = 0; i < splitCount; i++) {
            // generate different end timestamp for each split
            end = uint40(uint256(keccak256(abi.encode(end, i))));
            paramsList[i].end = uint40(bound(end, Math.max(paramsList[i].start + 1, parentLock.end), type(uint40).max));

            // re-generate cliff accordingly
            paramsList[i].cliff = uint40(bound(paramsList[i].cliff, 0, paramsList[i].end - paramsList[i].start));
        }
        _;
    }

    function testFuzz_WhenOneOfStartTimesIsSmallerThanParentLocksStartTime(
        uint40 start,
        uint40 end,
        uint40 cliff
    )
        external
        whenCallerIsAuthorized
        whenSplitParamatersListLengthIsNotZero
        whenNoneOfRecipientsIsAddressZero
        whenNoneOfAmountsIsZero
        whenNoneOfEndTimesIsEqualToStartTime
        whenAllEndTimesAreGreaterThanStartTime(start, end)
        whenAllCliffsAreEqualOrSmallerThanDuration(cliff)
        whenAllEndTimesAreEqualOrGreaterThanParentLocksEndTime(end)
    {
        uint256 salt = uint256(keccak256(abi.encodePacked(start, splitCount)));
        uint256 randomIndex = bound(salt, 0, splitCount - 1);

        // randomly choose an invalid start
        paramsList[randomIndex].start = uint40(bound(start, 0, parentLock.start));
        // update end and cliff accordingly
        paramsList[randomIndex].end = uint40(
            bound(end, Math.max(paramsList[randomIndex].start + 1, parentLock.end), type(uint40).max)
        );
        paramsList[randomIndex].cliff = uint40(
            bound(cliff, 0, paramsList[randomIndex].end - paramsList[randomIndex].start)
        );

        // It should revert with InvalidStart
        vm.expectRevert(IGovNFT.InvalidStart.selector);
        govNFT.split({_from: from, _paramsList: paramsList});
    }

    modifier whenAllStartTimesAreEqualOrGreaterThanParentLocksStartTime(uint40 start) {
        for (uint256 i = 0; i < splitCount; i++) {
            // generate different start timestamp for each split
            start = uint40(uint256(keccak256(abi.encode(start, i))));
            paramsList[i].start = uint40(bound(start, parentLock.start, type(uint40).max));

            // re-generate cliff and end timestamps accordingly
            paramsList[i].end = uint40(
                bound(paramsList[i].end, Math.max(paramsList[i].start + 1, parentLock.end), type(uint40).max)
            );
            paramsList[i].cliff = uint40(bound(paramsList[i].cliff, 0, paramsList[i].end - paramsList[i].start));
        }
        _;
    }

    function testFuzz_WhenOneOfStartTimesIsSmallerThanBlockTimestamp(
        uint40 start,
        uint40 end,
        uint40 cliff
    )
        external
        whenCallerIsAuthorized
        whenSplitParamatersListLengthIsNotZero
        whenNoneOfRecipientsIsAddressZero
        whenNoneOfAmountsIsZero
        whenNoneOfEndTimesIsEqualToStartTime
        whenAllEndTimesAreGreaterThanStartTime(start, end)
        whenAllCliffsAreEqualOrSmallerThanDuration(cliff)
        whenAllEndTimesAreEqualOrGreaterThanParentLocksEndTime(end)
        whenAllStartTimesAreEqualOrGreaterThanParentLocksStartTime(start)
    {
        uint256 salt = uint256(keccak256(abi.encodePacked(end, splitCount)));
        uint256 randomIndex = bound(salt, 0, splitCount - 1);

        // randomly choose an invalid start
        paramsList[randomIndex].start = uint40(bound(start, 0, block.timestamp - 1));

        // re-generate cliff and end timestamps accordingly
        paramsList[randomIndex].end = uint40(
            bound(end, Math.max(paramsList[randomIndex].start + 1, parentLock.end), type(uint40).max)
        );
        paramsList[randomIndex].cliff = uint40(
            bound(paramsList[randomIndex].cliff, 0, paramsList[randomIndex].end - paramsList[randomIndex].start)
        );

        // It should revert with InvalidStart
        vm.expectRevert(IGovNFT.InvalidStart.selector);
        govNFT.split({_from: from, _paramsList: paramsList});
    }

    modifier whenAllStartTimesAreEqualOrGreaterThanBlockTimestamp(uint40 start) {
        for (uint256 i = 0; i < splitCount; i++) {
            // generate different start timestamp for each split
            start = uint40(uint256(keccak256(abi.encode(start, i))));
            paramsList[i].start = uint40(bound(start, Math.max(block.timestamp, parentLock.start), type(uint40).max));

            // re-generate cliff and end timestamps accordingly
            paramsList[i].end = uint40(
                bound(paramsList[i].end, Math.max(paramsList[i].start + 1, parentLock.end), type(uint40).max)
            );
            paramsList[i].cliff = uint40(bound(paramsList[i].cliff, 0, paramsList[i].end - paramsList[i].start));
        }
        _;
    }

    function testFuzz_WhenOneOfCliffEndsIsSmallerThanParentLocksCliffEnd(
        uint40 start,
        uint40 end,
        uint40 cliff
    )
        external
        whenCallerIsAuthorized
        whenSplitParamatersListLengthIsNotZero
        whenNoneOfRecipientsIsAddressZero
        whenNoneOfAmountsIsZero
        whenNoneOfEndTimesIsEqualToStartTime
        whenAllEndTimesAreGreaterThanStartTime(start, end)
        whenAllCliffsAreEqualOrSmallerThanDuration(cliff)
        whenAllEndTimesAreEqualOrGreaterThanParentLocksEndTime(end)
        whenAllStartTimesAreEqualOrGreaterThanParentLocksStartTime(start)
        whenAllStartTimesAreEqualOrGreaterThanBlockTimestamp(start)
    {
        uint256 salt = uint256(keccak256(abi.encodePacked(end, splitCount)));
        uint256 randomIndex = bound(salt, 0, splitCount - 1);

        // re-generate new start and end to allow an invalid cliff
        uint40 parentCliffEnd = parentLock.start + parentLock.cliffLength;
        if (paramsList[randomIndex].start >= parentCliffEnd) {
            paramsList[randomIndex].start = uint40(
                bound(paramsList[randomIndex].start, Math.max(block.timestamp, parentLock.start), parentCliffEnd - 1)
            );
            paramsList[randomIndex].end = uint40(
                bound(
                    paramsList[randomIndex].end,
                    Math.max(paramsList[randomIndex].start + 1, parentLock.end),
                    type(uint40).max
                )
            );
        }
        // randomly choose an invalid cliff
        paramsList[randomIndex].cliff = uint40(bound(cliff, 0, parentCliffEnd - paramsList[randomIndex].start - 1));

        uint40 splitCliffEnd = paramsList[randomIndex].start + paramsList[randomIndex].cliff;
        assertLt(splitCliffEnd, parentCliffEnd);
        // It should revert with InvalidCliff
        vm.expectRevert(IGovNFT.InvalidCliff.selector);
        govNFT.split({_from: from, _paramsList: paramsList});
    }

    modifier whenAllCliffEndsAreEqualOrGreaterThanParentLocksCliffEnd(uint40 cliff) {
        uint40 minCliff;
        uint40 parentCliffEnd = parentLock.start + parentLock.cliffLength;
        for (uint256 i = 0; i < splitCount; i++) {
            // generate different cliff timestamp for each split
            minCliff = parentCliffEnd > paramsList[i].start ? parentCliffEnd - paramsList[i].start : 0;
            cliff = uint40(uint256(keccak256(abi.encode(cliff, i))));
            paramsList[i].cliff = uint40(bound(paramsList[i].cliff, minCliff, paramsList[i].end - paramsList[i].start));
        }
        _;
    }

    function testFuzz_WhenSumOfAllSplitAmountsIsGreaterThanCurrentParentLockedAmount(
        uint40 start,
        uint40 end,
        uint40 cliff,
        uint256 amount
    )
        external
        whenCallerIsAuthorized
        whenSplitParamatersListLengthIsNotZero
        whenNoneOfRecipientsIsAddressZero
        whenNoneOfAmountsIsZero
        whenNoneOfEndTimesIsEqualToStartTime
        whenAllEndTimesAreGreaterThanStartTime(start, end)
        whenAllCliffsAreEqualOrSmallerThanDuration(cliff)
        whenAllEndTimesAreEqualOrGreaterThanParentLocksEndTime(end)
        whenAllStartTimesAreEqualOrGreaterThanParentLocksStartTime(start)
        whenAllStartTimesAreEqualOrGreaterThanBlockTimestamp(start)
        whenAllCliffEndsAreEqualOrGreaterThanParentLocksCliffEnd(cliff)
    {
        uint256 sumOfAmounts;
        uint256 maxAmount = govNFT.locked(from);
        for (uint256 i = 0; i < splitCount; i++) {
            amount = uint256(keccak256(abi.encode(amount, i)));
            paramsList[i].amount = bound(amount, maxAmount / splitCount + 1, type(uint256).max / splitCount);
            sumOfAmounts += paramsList[i].amount;
        }
        assertGt(sumOfAmounts, govNFT.locked(from));
        // It should revert with AmountTooBig
        vm.expectRevert(IGovNFT.AmountTooBig.selector);
        govNFT.split({_from: from, _paramsList: paramsList});
    }

    modifier whenSumOfAllSplitAmountsIsEqualOrSmallerThanCurrentParentLockedAmount(uint256 amount) {
        for (uint256 i = 0; i < splitCount; i++) {
            amount = uint256(keccak256(abi.encode(amount, i)));
            paramsList[i].amount = bound(amount, 1, govNFT.locked(from) / splitCount);
        }
        _;
    }

    modifier givenVaultBalanceIsEqualOrGreaterThanAmount() {
        _;
    }

    function testFuzz_GivenBlockTimestampIsSmallerThanParentLockCliffEnd(
        uint40 start,
        uint40 end,
        uint40 cliff,
        uint256 amount
    )
        external
        whenCallerIsAuthorized
        whenSplitParamatersListLengthIsNotZero
        whenNoneOfRecipientsIsAddressZero
        whenNoneOfAmountsIsZero
        whenNoneOfEndTimesIsEqualToStartTime
        whenAllEndTimesAreGreaterThanStartTime(start, end)
        whenAllCliffsAreEqualOrSmallerThanDuration(cliff)
        whenAllEndTimesAreEqualOrGreaterThanParentLocksEndTime(end)
        whenAllStartTimesAreEqualOrGreaterThanParentLocksStartTime(start)
        whenAllStartTimesAreEqualOrGreaterThanBlockTimestamp(start)
        whenAllCliffEndsAreEqualOrGreaterThanParentLocksCliffEnd(cliff)
        whenSumOfAllSplitAmountsIsEqualOrSmallerThanCurrentParentLockedAmount(amount)
        givenVaultBalanceIsEqualOrGreaterThanAmount
    {
        uint256 parentLockedAmount = parentLock.totalLocked;
        IGovNFT.SplitParams memory params;
        // Expect one Split event per SplitParams
        for (uint256 i = 0; i < splitCount; i++) {
            params = paramsList[i];
            parentLockedAmount -= params.amount;

            vm.expectEmit(address(govNFT));
            // It should emit a {Split} event
            emit IGovNFT.Split({
                from: from,
                to: from + (i + 1),
                recipient: params.beneficiary,
                splitAmount1: parentLockedAmount,
                splitAmount2: params.amount,
                startTime: params.start,
                endTime: params.end,
                description: ""
            });
        }
        // It should emit a {MetadataUpdate} event
        vm.expectEmit(address(govNFT));
        emit IERC4906.MetadataUpdate(from);

        // Execute all Splits
        uint256[] memory splitIds = govNFT.split({_from: from, _paramsList: paramsList});

        // It should mint an NFT for each set of Split parameters
        assertEq(govNFT.tokenId(), from + splitCount);

        uint256 splitId;
        uint256 sumOfAmounts;
        IGovNFT.Lock memory splitLock;
        for (uint256 i = 0; i < splitCount; i++) {
            splitId = splitIds[i];
            params = paramsList[i];
            sumOfAmounts += params.amount;
            splitLock = govNFT.locks(splitId);

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
            assertEq(govNFT.splitTokensByIndex(from, i), splitId);
        }
        // It should add number of new split NFTs to parent's splitCount
        assertEq(govNFT.locks(from).splitCount, parentLock.splitCount + splitCount);
        // It should subtract sum of amounts from totalLocked in parent lock
        assertEq(govNFT.locks(from).totalLocked, parentLock.totalLocked - sumOfAmounts);
        // It should keep unclaimedBeforeSplit in parent lock set to 0
        assertEq(govNFT.locks(from).unclaimedBeforeSplit, 0);
        // It should delete parent lock total claimed
        assertEq(govNFT.locks(from).totalClaimed, 0);
    }

    function testFuzz_GivenBlockTimestampIsGreaterOrEqualToParentLockCliffEnd(
        uint40 start,
        uint40 end,
        uint40 cliff,
        uint256 amount,
        uint40 timeskip
    )
        external
        whenCallerIsAuthorized
        whenSplitParamatersListLengthIsNotZero
        whenNoneOfRecipientsIsAddressZero
        whenNoneOfAmountsIsZero
        whenNoneOfEndTimesIsEqualToStartTime
        whenAllEndTimesAreGreaterThanStartTime(start, end)
        whenAllCliffsAreEqualOrSmallerThanDuration(cliff)
        whenAllEndTimesAreEqualOrGreaterThanParentLocksEndTime(end)
        whenAllStartTimesAreEqualOrGreaterThanParentLocksStartTime(start)
        whenAllStartTimesAreEqualOrGreaterThanBlockTimestamp(start)
        whenAllCliffEndsAreEqualOrGreaterThanParentLocksCliffEnd(cliff)
        whenSumOfAllSplitAmountsIsEqualOrSmallerThanCurrentParentLockedAmount(amount)
        givenVaultBalanceIsEqualOrGreaterThanAmount
    {
        // warp after cliff's end and before parent lock's end
        timeskip = uint40(bound(timeskip, parentLock.start + parentLock.cliffLength, parentLock.end - 1));
        vm.warp(timeskip);
        for (uint256 i = 0; i < splitCount; i++) {
            // set new start after block.timestamp and new cliff accordingly
            paramsList[i].start = uint40(
                bound(paramsList[i].start, block.timestamp, paramsList[i].start + paramsList[i].cliff)
            );
            paramsList[i].cliff = uint40(bound(paramsList[i].cliff, 0, paramsList[i].end - paramsList[i].start));
            // re-generate amount based on new locked amount
            amount = uint256(keccak256(abi.encode(amount, i)));
            paramsList[i].amount = bound(amount, 1, govNFT.locked(from) / splitCount - 1);
        }

        uint256 oldLocked = govNFT.locked(from);
        uint256 oldUnclaimed = govNFT.unclaimed(from);

        IGovNFT.SplitParams memory params;
        // Expect one Split event per SplitParams
        for (uint256 i = 0; i < splitCount; i++) {
            params = paramsList[i];
            oldLocked -= params.amount;
            vm.expectEmit(address(govNFT));
            // It should emit a {Split} event
            emit IGovNFT.Split({
                from: from,
                to: from + (i + 1),
                recipient: params.beneficiary,
                splitAmount1: oldLocked,
                splitAmount2: params.amount,
                startTime: params.start,
                endTime: params.end,
                description: ""
            });
        }

        // It should emit a {MetadataUpdate} event
        vm.expectEmit(address(govNFT));
        emit IERC4906.MetadataUpdate(from);
        oldLocked = govNFT.locked(from); // cache oldLocked before splitting

        // Execute all Splits
        uint256[] memory splitIds = govNFT.split({_from: from, _paramsList: paramsList});

        // It should mint an NFT for each set of Split parameters
        assertEq(govNFT.tokenId(), from + splitCount);

        uint256 splitId;
        uint256 sumOfAmounts;
        IGovNFT.Lock memory splitLock;
        for (uint256 i = 0; i < splitCount; i++) {
            splitId = splitIds[i];
            params = paramsList[i];
            sumOfAmounts += params.amount;
            splitLock = govNFT.locks(splitId);

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
            assertEq(govNFT.splitTokensByIndex(from, i), splitId);
        }
        // It should add number of new split NFTs to parent's splitCount
        assertEq(govNFT.locks(from).splitCount, parentLock.splitCount + splitCount);
        // It should subtract sum of amounts from totalLocked in parent lock
        assertEq(govNFT.locks(from).totalLocked, oldLocked - sumOfAmounts);
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
