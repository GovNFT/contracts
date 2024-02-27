// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "test/utils/BaseTest.sol";
import "src/GovNFTTimelockFactory.sol";
import "src/interfaces/IGovNFT.sol";
import "src/interfaces/IGovNFTTimelock.sol";
import "src/interfaces/IGovNFTTimelockFactory.sol";

contract GovNFTTimelockFactoryTest is BaseTest {
    IGovNFTTimelockFactory factory;
    address public artProxy = vm.addr(0x12345);
    uint256 public timelock = 0; //TODO: set timelock

    function _setUp() public override {
        factory = new GovNFTTimelockFactory(artProxy, NAME, SYMBOL, timelock);
    }

    function testSetup() public {
        assertFalse(factory.govNFT() == address(0));
        assertEq(factory.govNFTsLength(), 1);
        assertTrue(factory.isGovNFT(factory.govNFT()));
        address[] memory govNFTs = factory.govNFTs();
        address _govNFT = govNFTs[0];
        assertEq(govNFTs.length, 1);
        assertEq(_govNFT, factory.govNFT());
        assertEq(ERC721(_govNFT).name(), NAME);
        assertEq(ERC721(_govNFT).symbol(), SYMBOL);
        assertEq(Ownable(_govNFT).owner(), address(factory));
        assertEq(IGovNFTTimelock(_govNFT).timelock(), timelock);
    }

    function testCannotCreateWithFactoryAsAdmin() public {
        vm.expectRevert(IGovNFTTimelockFactory.NotAuthorized.selector);
        factory.createGovNFT(address(factory), address(0), NAME, SYMBOL, timelock);
    }

    function testCreateGovNFT() public {
        address customArtProxy = vm.addr(0x54321);
        assertEq(factory.govNFTsLength(), 1);
        address _govNFT = factory.createGovNFT(
            address(admin),
            customArtProxy,
            "CustomGovNFTTimelock",
            "CustomGovNFT",
            timelock
        );
        assertEq(factory.govNFTsLength(), 2);
        address[] memory govNFTs = factory.govNFTs();
        assertEq(govNFTs.length, 2);
        assertTrue(govNFTs[1] == _govNFT);
        assertEq(ERC721(_govNFT).name(), "CustomGovNFTTimelock");
        assertEq(ERC721(_govNFT).symbol(), "CustomGovNFT");
        assertEq(Ownable(_govNFT).owner(), address(admin));
        assertEq(IGovNFT(_govNFT).artProxy(), customArtProxy);
        assertEq(IGovNFTTimelock(_govNFT).timelock(), timelock);
    }

    function testCanCreateLockIfNotOwnerInPermissionlessGovNFT() public {
        IGovNFT _govNFT = IGovNFT(factory.govNFT());

        admin.approve(testToken, address(_govNFT), TOKEN_100K);
        vm.prank(address(admin));
        _govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 2,
            WEEK
        );
        notAdmin.approve(testToken, address(_govNFT), TOKEN_100K);
        vm.prank(address(notAdmin));
        _govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 2,
            WEEK
        );
    }

    function testCannotCreateLockIfNotOwner() public {
        IGovNFT _govNFT = IGovNFT(factory.createGovNFT(address(admin), artProxy, NAME, SYMBOL, timelock));

        admin.approve(testToken, address(_govNFT), TOKEN_100K);
        vm.prank(address(admin));
        _govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 2,
            WEEK
        );
        notAdmin.approve(testToken, address(_govNFT), TOKEN_100K);
        vm.prank(address(notAdmin));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(notAdmin)));
        _govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            block.timestamp,
            block.timestamp + WEEK * 2,
            WEEK
        );
    }
}
