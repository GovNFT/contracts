// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockERC20} from "test/utils/MockERC20.sol";
import {TimeStore} from "test/invariants/TimeStore.sol";
import {GovNFTHandler} from "test/invariants/handler/GovNFTHandler.sol";
import {IGovNFT} from "src/interfaces/IGovNFT.sol";

abstract contract GovNFTInvariants is Test {
    IGovNFT public govNFT;
    TimeStore public timestore;
    GovNFTHandler public handler;

    address public testToken;
    address public airdropToken;

    string constant NAME = "GovNFT: NFT for vested distribution of (governance) tokens";
    string constant SYMBOL = "GOVNFT";

    function setUp() public {
        timestore = new TimeStore(2 seconds);
        testToken = address(new MockERC20("TEST", "TEST", 18));
        airdropToken = address(new MockERC20("AIRDROP", "AIRDROP", 18));

        _setUp();
        targetContract(address(handler));
        excludeArtifact("src/Vault.sol:Vault"); // avoid calling vaults created during execution

        vm.label(testToken, "TestToken");
        vm.label(address(handler), "Handler");
        vm.label(airdropToken, "AirdropToken");
    }

    function _setUp() internal virtual;

    modifier useCurrentTimestamp() {
        vm.warp(timestore.currentTimestamp());
        vm.roll(timestore.currentBlockNumber());
        _;
    }

    function invariant_sumOfTotalLockedEqualToTotalDeposited() external useCurrentTimestamp {
        uint256 length = govNFT.tokenId();

        uint256 claimable;
        uint256 lockTokenSum;
        uint256 totalLockedSum;
        uint256 claimsBeforeSplit;
        IGovNFT.Lock memory lock;
        for (uint256 i = 1; i < length + 1; i++) {
            lock = govNFT.locks(i);

            claimable = govNFT.unclaimed(i);
            // @dev Claims before Split are calculated manually, since Split resets `totalClaimed`
            claimsBeforeSplit = handler.idToPersistentClaims(i) - lock.totalClaimed;
            totalLockedSum += lock.totalLocked + lock.unclaimedBeforeSplit + claimsBeforeSplit;
            lockTokenSum += claimable + govNFT.locked(i) + handler.idToPersistentClaims(i);
            assertEq(
                govNFT.totalVested(i),
                claimable + lock.totalClaimed - lock.unclaimedBeforeSplit,
                "Invariant: Total Vested == Unclaimed + Total Claimed"
            );
        }
        assertEq(totalLockedSum, handler.totalDeposited(), "Invariant: Sum of Total Locked == Total Deposit");
        assertEq(
            lockTokenSum,
            handler.totalDeposited(),
            "Invariant: Sum of Locked, Vested and Claimed tokens == Total Deposit"
        );
    }

    function invariant_vaultBalancesGreaterThanLockTokens() external useCurrentTimestamp {
        uint256 length = govNFT.tokenId();

        uint256 vaultSum;
        uint256 claimSum;
        uint256 vaultBalance;
        IGovNFT.Lock memory lock;
        for (uint256 i = 1; i < length + 1; i++) {
            lock = govNFT.locks(i);

            vaultBalance = IERC20(testToken).balanceOf(lock.vault);
            claimSum += handler.idToPersistentClaims(i);
            vaultSum += vaultBalance;

            assertGe(
                vaultBalance,
                govNFT.locked(i) + govNFT.unclaimed(i),
                "Invariant: Vault Balance >= Locked + Unclaimed Tokens"
            );
        }
        assertGe(
            vaultSum,
            handler.totalDeposited() - claimSum,
            "Invariant: Sum of Vault Balances >= Total Deposit - Sum of Claimed Tokens"
        );
    }

    function invariant_sweepOnlyTransfersAirdroppedTokens() external useCurrentTimestamp {
        uint256 length = govNFT.tokenId();

        address owner;
        uint256 amount = 1e23;
        uint256 balanceAfter;
        uint256 balanceBefore;
        uint256 vaultBalanceAfter;
        uint256 vaultBalanceBefore;
        IGovNFT.Lock memory lock;

        for (uint256 i = 1; i < length + 1; i++) {
            lock = govNFT.locks(i);

            if (block.timestamp >= lock.end) {
                owner = govNFT.ownerOf(i);
                deal(lock.token, lock.vault, IERC20(lock.token).balanceOf(lock.vault) + amount);

                vaultBalanceBefore = IERC20(lock.token).balanceOf(lock.vault);
                balanceBefore = IERC20(lock.token).balanceOf(owner);

                vm.prank(owner);
                govNFT.sweep({_tokenId: i, _token: lock.token, _recipient: owner});

                // can only claim airdropped tokens
                balanceAfter = IERC20(lock.token).balanceOf(owner);
                assertGt(balanceAfter, balanceBefore);
                assertEq(balanceAfter - balanceBefore, amount);

                vaultBalanceAfter = IERC20(lock.token).balanceOf(lock.vault);
                assertLt(vaultBalanceAfter, vaultBalanceBefore);
                assertEq(vaultBalanceBefore - vaultBalanceAfter, amount);
            }
        }
    }

    function invariant_sumOfChildLocksEqualToTotalDeposit() external useCurrentTimestamp {
        uint256 length = govNFT.tokenId();

        uint256 sum;
        uint256 claimsBeforeSplit;
        IGovNFT.Lock memory lock;
        for (uint256 i = 1; i < length + 1; i++) {
            lock = govNFT.locks(i);

            sum = _getSumOfChildLocks(i, lock);
            claimsBeforeSplit = handler.idToPersistentClaims(i) - lock.totalClaimed;
            assertEq(
                sum + lock.totalLocked + lock.unclaimedBeforeSplit + claimsBeforeSplit,
                lock.initialDeposit,
                "Invariant: Sum of all Child and Parent Lock's Tokens == Parent Lock's Initial Deposit"
            );
        }
    }

    // @dev Recursive function to calculate the sum of the Child Lock's tokens for a given `_tokenId`
    function _getSumOfChildLocks(uint256 _tokenId, IGovNFT.Lock memory _lock) internal view returns (uint256 sum) {
        if (_lock.splitCount > 0) {
            uint256 childId;
            uint256 sumOfChildLocks;
            uint256 claimsBeforeSplit;
            IGovNFT.Lock memory childLock;
            for (uint256 i = 0; i < _lock.splitCount; i++) {
                childId = govNFT.splitTokensByIndex(_tokenId, i);
                childLock = govNFT.locks(childId);

                claimsBeforeSplit = handler.idToPersistentClaims(childId) - childLock.totalClaimed;
                // @dev Recursively call `_getSumOfChildLocks` if Child Lock has children
                sumOfChildLocks = childLock.splitCount > 0 ? _getSumOfChildLocks(childId, childLock) : 0;
                sum += childLock.totalLocked + childLock.unclaimedBeforeSplit + claimsBeforeSplit + sumOfChildLocks;
            }
        }
    }
}
