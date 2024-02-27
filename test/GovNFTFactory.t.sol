// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract GovNFTFactoryTest is BaseTest {
    IGovNFTFactory factory;
    address public artProxy = vm.addr(0x12345);

    function _setUp() public override {
        factory = new GovNFTFactory(artProxy, NAME, SYMBOL);
    }

    function test_Setup() public {
        assertFalse(factory.govNFT() == address(0));
        assertEq(factory.govNFTsLength(), 1);
        assertTrue(factory.isGovNFT(factory.govNFT()));

        address[] memory govNFTs = factory.govNFTs();
        GovNFTSplit _govNFT = GovNFTSplit(govNFTs[0]);
        assertEq(govNFTs.length, 1);
        assertEq(address(_govNFT), factory.govNFT());

        assertEq(_govNFT.name(), NAME);
        assertEq(_govNFT.symbol(), SYMBOL);
        assertEq(_govNFT.owner(), address(factory));
    }

    function test_RevertIf_CreateWithFactoryAsAdmin() public {
        vm.expectRevert(IGovNFTFactory.NotAuthorized.selector);
        factory.createGovNFT({_owner: address(factory), _artProxy: address(0), _name: NAME, _symbol: SYMBOL});
    }

    function test_CreateGovNFT() public {
        address customArtProxy = vm.addr(0x54321);
        assertEq(factory.govNFTsLength(), 1);

        GovNFTSplit _govNFT = GovNFTSplit(
            factory.createGovNFT({
                _owner: address(admin),
                _artProxy: customArtProxy,
                _name: "CustomGovNFT",
                _symbol: "CustomGovNFT"
            })
        );
        assertEq(factory.govNFTsLength(), 2);
        address[] memory govNFTs = factory.govNFTs();
        assertEq(govNFTs.length, 2);
        assertTrue(govNFTs[1] == address(_govNFT));

        assertEq(_govNFT.name(), "CustomGovNFT");
        assertEq(_govNFT.symbol(), "CustomGovNFT");
        assertEq(_govNFT.owner(), address(admin));
        assertEq(_govNFT.artProxy(), customArtProxy);
    }

    function test_CanCreateLockIfNotOwnerInPermissionlessGovNFT() public {
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

    function test_RevertIf_CreateLockIfNotOwner() public {
        IGovNFT _govNFT = IGovNFT(
            factory.createGovNFT({_owner: address(admin), _artProxy: artProxy, _name: NAME, _symbol: SYMBOL})
        );

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
