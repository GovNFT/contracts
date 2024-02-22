// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "test/utils/BaseTest.sol";
import "src/GovNFTFactory.sol";
import "src/interfaces/IGovNFT.sol";
import "src/interfaces/IGovNFTFactory.sol";

contract FactoryTest is BaseTest {
    IGovNFTFactory factory;
    address public artProxy = vm.addr(0x12345);

    function _setUp() public override {
        factory = new GovNFTFactory(artProxy, "GovNFT", "GovNFT");
    }

    function testSetup() public {
        assertFalse(factory.govNFT() == address(0));
        assertEq(factory.govNFTsLength(), 1);
        assertTrue(factory.isGovNFT(factory.govNFT()));
        address[] memory govNFTs = factory.govNFTs();
        address _govNFT = govNFTs[0];
        assertEq(govNFTs.length, 1);
        assertEq(_govNFT, factory.govNFT());
        assertEq(ERC721(_govNFT).name(), "GovNFT");
        assertEq(ERC721(_govNFT).symbol(), "GovNFT");
        assertEq(Ownable(_govNFT).owner(), address(factory));
    }

    function testCannotCreateWithFactoryAsAdmin() public {
        vm.expectRevert(IGovNFTFactory.NotAuthorized.selector);
        factory.createGovNFT(address(factory), address(0), "GovNFT", "GovNFT");
    }

    function testCreateGovNFT() public {
        address customArtProxy = vm.addr(0x54321);
        assertEq(factory.govNFTsLength(), 1);
        address _govNFT = factory.createGovNFT(address(admin), customArtProxy, "CustomGovNFT", "CustomGovNFT");
        assertEq(factory.govNFTsLength(), 2);
        address[] memory govNFTs = factory.govNFTs();
        assertEq(govNFTs.length, 2);
        assertTrue(govNFTs[1] == _govNFT);
        assertEq(ERC721(_govNFT).name(), "CustomGovNFT");
        assertEq(ERC721(_govNFT).symbol(), "CustomGovNFT");
        assertEq(Ownable(_govNFT).owner(), address(admin));
        assertEq(IGovNFT(_govNFT).artProxy(), customArtProxy);
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
        IGovNFT _govNFT = IGovNFT(factory.createGovNFT(address(admin), artProxy, "GovNFT", "GovNFT"));

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
