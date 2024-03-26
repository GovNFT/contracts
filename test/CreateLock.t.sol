// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract LockTest is BaseTest {
    function test_CreateLock() public {
        assertEq(govNFT.totalSupply(), 0);
        assertEq(govNFT.balanceOf(address(recipient)), 0);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);

        admin.approve(testToken, address(govNFT), TOKEN_100K);

        vm.expectEmit(true, true, true, true, address(govNFT));
        emit IGovNFT.Create({
            tokenId: 1,
            recipient: address(recipient),
            token: testToken,
            amount: TOKEN_100K,
            description: ""
        });
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_100K,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 2,
            _cliffLength: WEEK,
            _description: ""
        });

        assertEq(govNFT.totalSupply(), 1);
        assertEq(govNFT.balanceOf(address(recipient)), 1);
        assertEq(govNFT.tokenOfOwnerByIndex(address(recipient), 0), tokenId);

        assertEq(govNFT.ownerOf(tokenId), address(recipient));

        IGovNFT.Lock memory lock = govNFT.locks(tokenId);

        assertEq(lock.cliffLength, WEEK);
        assertEq(lock.start, uint40(block.timestamp));
        assertEq(lock.end, uint40(block.timestamp) + WEEK * 2);

        assertEq(lock.totalClaimed, 0);
        assertEq(lock.totalLocked, TOKEN_100K);
        assertEq(lock.initialDeposit, TOKEN_100K);

        assertEq(Vault(lock.vault).token(), address(testToken));
        assertEq(lock.token, address(testToken));
        assertEq(lock.minter, address(admin));

        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(govNFT)), 0);
    }

    function test_RevertIf_CreateLockToZeroAddress() public {
        vm.expectRevert(IGovNFT.ZeroAddress.selector);
        vm.prank(address(admin));
        govNFT.createLock({
            _token: address(0),
            _recipient: address(recipient),
            _amount: TOKEN_1,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 2,
            _cliffLength: WEEK,
            _description: ""
        });

        vm.expectRevert(IGovNFT.ZeroAddress.selector);
        vm.prank(address(admin));
        govNFT.createLock({
            _token: testToken,
            _recipient: address(0),
            _amount: TOKEN_1,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 2,
            _cliffLength: WEEK,
            _description: ""
        });
    }

    function test_RevertIf_CreateLockWithZeroAmount() public {
        vm.expectRevert(IGovNFT.ZeroAmount.selector);
        vm.prank(address(admin));
        govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: 0,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 2,
            _cliffLength: WEEK,
            _description: ""
        });
    }

    function test_RevertIf_CreateLockWithInvalidCliff() public {
        vm.expectRevert(IGovNFT.InvalidCliff.selector);
        vm.prank(address(admin));
        govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_1,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK - 1,
            _cliffLength: WEEK,
            _description: ""
        });
    }

    function test_RevertIf_CreateLockWithZeroDuration() public {
        vm.expectRevert(IGovNFT.InvalidParameters.selector);
        vm.prank(address(admin));
        govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_1,
            _startTime: uint40(block.timestamp) + WEEK,
            _endTime: uint40(block.timestamp) + WEEK,
            _cliffLength: WEEK,
            _description: ""
        });
    }

    function test_RevertIf_CreateLockIfNotEnoughTokensTransferred() public {
        // deploy mock erc-20 with fees, that does not transfer all tokens to recipient
        address token = address(new MockFeeERC20("TEST", "TEST", 18));
        deal(token, address(admin), TOKEN_100K);

        vm.startPrank(address(admin));
        admin.approve(token, address(govNFT), TOKEN_100K);
        vm.expectRevert(IGovNFT.InsufficientAmount.selector);
        govNFT.createLock({
            _token: token,
            _recipient: address(recipient),
            _amount: TOKEN_100K,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 2,
            _cliffLength: WEEK,
            _description: ""
        });
    }

    function test_RevertIf_CreateLockWithEndBeforeStart() public {
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(address(admin));
        govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_1,
            _startTime: uint40(block.timestamp) + WEEK * 2,
            _endTime: uint40(block.timestamp) + WEEK,
            _cliffLength: WEEK,
            _description: ""
        });

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(address(admin));
        govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_1,
            _startTime: uint40(block.timestamp) + WEEK + 1,
            _endTime: uint40(block.timestamp) + WEEK,
            _cliffLength: WEEK,
            _description: ""
        });
    }

    function test_RevertIf_CreateLockWhenStartIsInPast() public {
        vm.expectRevert(IGovNFT.InvalidStart.selector);
        vm.prank(address(admin));
        govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_1,
            _startTime: uint40(block.timestamp) - 1,
            _endTime: uint40(block.timestamp) + WEEK * 2,
            _cliffLength: WEEK,
            _description: ""
        });
    }
}
