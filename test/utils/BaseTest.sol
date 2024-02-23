// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import {Test, console} from "forge-std/Test.sol";
import {MockERC20} from "test/utils/MockERC20.sol";
import {TestOwner} from "test/utils/TestOwner.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockGovernanceToken} from "test/utils/MockGovernanceToken.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {IGovNFTTimelock} from "src/interfaces/IGovNFTTimelock.sol";
import {IGovNFT} from "src/interfaces/IGovNFT.sol";
import "src/extensions/GovNFTTimelock.sol";
import "src/extensions/GovNFTSplit.sol";

contract BaseTest is Test {
    GovNFTSplit public govNFT;

    address public testToken;
    address public testGovernanceToken;
    address public airdropToken;
    TestOwner public admin;
    TestOwner public recipient;
    TestOwner public recipient2;
    TestOwner public airdropper;
    TestOwner public notAdmin;

    uint256 constant TOKEN_1 = 1e18;
    uint256 constant TOKEN_10K = 1e22; // 1e4 = 10K tokens with 18 decimals
    uint256 constant TOKEN_100K = 1e23; // 1e5 = 100K tokens with 18 decimals
    uint256 constant TOKEN_1M = 1e24; // 1e6 = 1M tokens with 18 decimals
    uint256 constant TOKEN_10M = 1e25; // 1e7 = 10M tokens with 18 decimals
    uint256 constant TOKEN_100M = 1e26; // 1e8 = 100M tokens with 18 decimals
    uint256 constant TOKEN_10B = 1e28; // 1e10 = 10B tokens with 18 decimals
    uint256 constant POOL_1 = 1e9;

    uint256 constant DURATION = 7 days;
    uint256 constant WEEK = 1 weeks;

    string constant NAME = "GovNFT: NFT for vested distribution of (governance) tokens";
    string constant SYMBOL = "GOVNFT";

    function setUp() public {
        admin = new TestOwner();
        notAdmin = new TestOwner();
        recipient = new TestOwner();
        recipient2 = new TestOwner();
        airdropper = new TestOwner();

        vm.prank(address(admin));
        govNFT = new GovNFTSplit(address(admin), address(0), NAME, SYMBOL);

        testToken = address(new MockERC20("TEST", "TEST", 18));
        testGovernanceToken = address(new MockGovernanceToken("TESTGOV", "TESTGOV", 18));
        airdropToken = address(new MockERC20("AIRDROP", "AIRDROP", 18));
        deal(airdropToken, address(airdropper), TOKEN_100K);
        deal(testToken, address(airdropper), TOKEN_100K);
        deal(testToken, address(admin), TOKEN_100K);
        deal(testToken, address(notAdmin), TOKEN_100K);
        deal(testGovernanceToken, address(admin), TOKEN_100K);
        _setUp();
    }

    /// @dev Implement this if you want a custom configured deployment
    function _setUp() public virtual {}

    function _checkLockUpdates(
        uint256 tokenId,
        uint256 _totalLocked,
        uint256 _initialDeposit,
        uint256 _cliffLength,
        uint256 _start,
        uint256 _end
    ) internal {
        // Check TokenId's NFT information is equal to the input parameters
        (uint256 totalLocked, uint256 initialDeposit, , , , uint256 cliff, uint256 start, uint256 end, , , ) = govNFT
            .locks(tokenId);
        assertEq(totalLocked, _totalLocked);
        assertEq(initialDeposit, _initialDeposit);
        assertEq(cliff, _cliffLength);
        assertEq(start, _start);
        assertEq(end, _end);
    }

    function _checkSplitInfo(
        uint256 _from,
        uint256 tokenId,
        address owner,
        address beneficiary,
        uint256 unclaimedBeforeSplit,
        uint256 splitCount
    ) internal {
        // Asserts that information retrieved from tokens involved in split is equal to given parameters
        _checkBatchSplitInfo(_from, tokenId, owner, beneficiary, unclaimedBeforeSplit, splitCount, 0);
    }

    function _checkBatchSplitInfo(
        uint256 _from,
        uint256 tokenId,
        address owner,
        address beneficiary,
        uint256 unclaimedBeforeSplit,
        uint256 splitCount,
        uint256 splitIndex
    ) internal {
        // Asserts that information retrieved from tokens involved in split is equal to given parameters
        assertEq(govNFT.ownerOf(_from), owner);
        assertEq(govNFT.ownerOf(tokenId), beneficiary);

        (, , uint256 _totalClaimed, , , , , , address splitToken, , address minter) = govNFT.locks(tokenId);

        (, , , uint256 _unclaimedBeforeSplit, uint256 _splitCount, , , , address token, , ) = govNFT.locks(_from);
        assertEq(minter, owner);
        assertEq(_totalClaimed, 0);
        assertEq(token, splitToken);
        assertEq(_splitCount, splitCount);
        assertEq(govNFT.splitTokensByIndex(_from, splitIndex), tokenId);
        assertEq(_unclaimedBeforeSplit, unclaimedBeforeSplit);
    }

    function _checkLockedUnclaimedSplit(
        uint256 _from,
        uint256 locked,
        uint256 unclaimed,
        uint256 _tokenId,
        uint256 locked2,
        uint256 unclaimed2
    ) internal {
        // Asserts that Locked and Unclaimed values retrieved from tokens are equal to given parameters
        assertEq(govNFT.locked(_from), locked);
        assertEq(govNFT.unclaimed(_from), unclaimed);

        assertEq(govNFT.locked(_tokenId), locked2);
        assertEq(govNFT.unclaimed(_tokenId), unclaimed2);
    }
}
