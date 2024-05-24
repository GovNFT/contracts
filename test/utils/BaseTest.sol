// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import {stdError} from "forge-std/StdError.sol";
import {TestOwner} from "test/utils/TestOwner.sol";
import {MockERC20} from "test/utils/MockERC20.sol";
import {MockFeeERC20} from "test/utils/MockFeeERC20.sol";
import {Test, stdStorage, console} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockGovernanceToken} from "test/utils/MockGovernanceToken.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC721Errors} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {GovNFTTimelockFactory, IGovNFTTimelockFactory} from "src/GovNFTTimelockFactory.sol";
import {GovNFTTimelock, IGovNFTTimelock} from "src/extensions/GovNFTTimelock.sol";

import {GovNFT} from "src/GovNFT.sol";
import {IGovNFT} from "src/interfaces/IGovNFT.sol";
import {GovNFTFactory, IGovNFTFactory} from "src/GovNFTFactory.sol";

import {IArtProxy} from "src/interfaces/IArtProxy.sol";
import {IGovNFT} from "src/interfaces/IGovNFT.sol";

import {Vault, IVault} from "src/Vault.sol";
import {ArtProxy} from "src/art/ArtProxy.sol";

contract BaseTest is Test {
    GovNFT public govNFT;
    IArtProxy public artProxy;
    IGovNFTFactory public factory;
    address public vaultImplementation;

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

    uint40 constant WEEK = 1 weeks;
    uint256 constant YEAR = 365 days;
    uint256 constant MONTH = 30 days;

    string constant NAME = "GovNFT: NFT for vested distribution of (governance) tokens";
    string constant SYMBOL = "GOVNFT";

    function setUp() public {
        admin = new TestOwner();
        notAdmin = new TestOwner();
        recipient = new TestOwner();
        recipient2 = new TestOwner();
        airdropper = new TestOwner();

        artProxy = new ArtProxy();

        vm.prank(address(admin));
        vaultImplementation = address(new Vault());
        factory = new GovNFTFactory({
            _vaultImplementation: vaultImplementation,
            _artProxy: address(artProxy),
            _name: NAME,
            _symbol: SYMBOL
        });
        govNFT = GovNFT(
            factory.createGovNFT({
                _owner: address(admin),
                _artProxy: address(artProxy),
                _name: NAME,
                _symbol: SYMBOL,
                _earlySweepLockToken: true
            })
        );

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
        uint40 _cliffLength,
        uint40 _start,
        uint40 _end
    ) internal {
        // Check TokenId's NFT information is equal to the input parameters
        IGovNFT.Lock memory lock = govNFT.locks(tokenId);
        assertEq(lock.totalLocked, _totalLocked);
        assertEq(lock.initialDeposit, _initialDeposit);
        assertEq(lock.cliffLength, _cliffLength);
        assertEq(lock.start, _start);
        assertEq(lock.end, _end);
    }

    function _checkSplitInfo(
        uint256 _from,
        uint256 tokenId,
        address owner,
        address beneficiary,
        uint256 unclaimedBeforeSplit,
        uint40 splitCount
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
        uint40 splitCount,
        uint256 splitIndex
    ) internal {
        // Asserts that information retrieved from tokens involved in split is equal to given parameters
        assertEq(govNFT.ownerOf(_from), owner);
        assertEq(govNFT.ownerOf(tokenId), beneficiary);

        IGovNFT.Lock memory splitLock = govNFT.locks(tokenId);

        IGovNFT.Lock memory parentLock = govNFT.locks(_from);
        assertEq(splitLock.minter, owner);
        assertEq(splitLock.totalClaimed, 0);
        assertEq(parentLock.token, splitLock.token);
        assertEq(parentLock.splitCount, splitCount);
        assertEq(govNFT.splitTokensByIndex(_from, splitIndex), tokenId);
        assertEq(parentLock.unclaimedBeforeSplit, unclaimedBeforeSplit);
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
