// SPDX-License-Identifier: GPL-3.0-or-later
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

    function test_CreateRetroactiveLock() public {
        //make sure current time is more than 10 days
        skip(10 days);

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
        //create lock with 10% already vested
        vm.prank(address(admin));
        uint256 tokenId = govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_100K,
            _startTime: uint40(block.timestamp - 10 days),
            _endTime: uint40(block.timestamp + 90 days),
            _cliffLength: 0,
            _description: ""
        });

        IGovNFT.Lock memory lock = govNFT.locks(tokenId);

        assertEq(lock.start, uint40(block.timestamp - 10 days));
        assertEq(lock.end, uint40(block.timestamp + 90 days));
        assertEq(lock.totalLocked, TOKEN_100K);
        assertEq(govNFT.totalVested(tokenId), TOKEN_100K / 10);
        assertEq(govNFT.unclaimed(tokenId), TOKEN_100K / 10);
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked);
        assertEq(IERC20(testToken).balanceOf(address(recipient)), 0);

        vm.prank(address(recipient));
        govNFT.claim(tokenId, address(recipient), TOKEN_100K);

        assertEq(IERC20(testToken).balanceOf(address(recipient)), TOKEN_100K / 10);
        assertEq(IERC20(testToken).balanceOf(lock.vault), lock.totalLocked - TOKEN_100K / 10);
        assertEq(govNFT.unclaimed(tokenId), 0);

        lock = govNFT.locks(tokenId);
        assertEq(lock.totalClaimed, TOKEN_100K / 10);
    }
}
