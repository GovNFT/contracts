// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import "forge-std/console.sol";
import {Test, console2} from "forge-std/Test.sol";
import {MockERC20} from "test/utils/MockERC20.sol";
import {MockGovernanceToken} from "test/utils/MockGovernanceToken.sol";
import {TestOwner} from "test/utils/TestOwner.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {IVestingEscrow} from "src/interfaces/IVestingEscrow.sol";
import "src/VestingEscrow.sol";

contract BaseTest is Test {
    VestingEscrow public govNFT;

    address public testToken;
    address public testGovernanceToken;
    address public airdropToken;
    TestOwner public admin;
    TestOwner public recipient;
    TestOwner public airdropper;

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

    function setUp() public {
        govNFT = new VestingEscrow();

        admin = new TestOwner();
        recipient = new TestOwner();
        airdropper = new TestOwner();

        testToken = address(new MockERC20("TEST", "TEST", 18));
        testGovernanceToken = address(new MockGovernanceToken("TESTGOV", "TESTGOV", 18));
        airdropToken = address(new MockERC20("AIRDROP", "AIRDROP", 18));
        deal(airdropToken, address(airdropper), TOKEN_100K);
        deal(testToken, address(airdropper), TOKEN_100K);
        deal(testToken, address(admin), TOKEN_100K);
        deal(testGovernanceToken, address(admin), TOKEN_100K);
        _setUp();
    }

    /// @dev Implement this if you want a custom configured deployment
    function _setUp() public virtual {}
}
