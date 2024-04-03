// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract GovNFTFactoryTest is BaseTest {
    IGovNFTFactory factory;

    function _setUp() public override {
        factory = new GovNFTFactory({_artProxy: address(artProxy), _name: NAME, _symbol: SYMBOL});
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
        assertFalse(_govNFT.earlySweepLockToken());
        assertEq(_govNFT.owner(), address(factory));
    }

    function test_RevertIf_CreateWithFactoryAsAdmin() public {
        vm.expectRevert(IGovNFTFactory.NotAuthorized.selector);
        factory.createGovNFT({
            _owner: address(factory),
            _artProxy: address(0),
            _name: NAME,
            _symbol: SYMBOL,
            _earlySweepLockToken: true
        });
    }

    function test_CreateGovNFT() public {
        address customArtProxy = vm.addr(0x54321);
        assertEq(factory.govNFTsLength(), 1);

        GovNFTSplit _govNFT = GovNFTSplit(
            factory.createGovNFT({
                _owner: address(admin),
                _artProxy: customArtProxy,
                _name: "CustomGovNFT",
                _symbol: "CustomGovNFT",
                _earlySweepLockToken: true
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
        assertTrue(_govNFT.earlySweepLockToken());
    }

    function test_CanCreateLockIfNotOwnerInPermissionlessGovNFT() public {
        IGovNFT _govNFT = IGovNFT(factory.govNFT());

        admin.approve(testToken, address(_govNFT), TOKEN_100K);
        vm.prank(address(admin));
        _govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_100K,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 2,
            _cliffLength: WEEK,
            _description: ""
        });
        notAdmin.approve(testToken, address(_govNFT), TOKEN_100K);
        vm.prank(address(notAdmin));
        _govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_100K,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 2,
            _cliffLength: WEEK,
            _description: ""
        });
    }

    function test_RevertIf_CreateLockIfNotOwner() public {
        IGovNFT _govNFT = IGovNFT(
            factory.createGovNFT({
                _owner: address(admin),
                _artProxy: address(artProxy),
                _name: NAME,
                _symbol: SYMBOL,
                _earlySweepLockToken: true
            })
        );

        admin.approve(testToken, address(_govNFT), TOKEN_100K);
        vm.prank(address(admin));
        _govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_100K,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 2,
            _cliffLength: WEEK,
            _description: ""
        });
        notAdmin.approve(testToken, address(_govNFT), TOKEN_100K);
        vm.prank(address(notAdmin));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(notAdmin)));
        _govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_100K,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 2,
            _cliffLength: WEEK,
            _description: ""
        });
    }

    function test_TransferOwnership() public {
        vm.startPrank(address(admin));
        GovNFTSplit _govNFT = GovNFTSplit(
            factory.createGovNFT({
                _owner: address(admin),
                _artProxy: address(artProxy),
                _name: NAME,
                _symbol: SYMBOL,
                _earlySweepLockToken: true
            })
        );

        assertEq(_govNFT.owner(), address(admin));
        _govNFT.transferOwnership(address(notAdmin));
        assertEq(_govNFT.owner(), address(notAdmin));
    }

    function test_RevertIf_TransferOwnership_WhenNotOwnerOfGovNFT() public {
        GovNFTSplit _govNFT = GovNFTSplit(factory.govNFT());
        assertEq(_govNFT.owner(), address(factory));

        vm.prank(address(notAdmin));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(notAdmin)));
        _govNFT.transferOwnership(address(notAdmin));

        vm.prank(address(admin));
        _govNFT = GovNFTSplit(
            factory.createGovNFT({
                _owner: address(admin),
                _artProxy: address(artProxy),
                _name: NAME,
                _symbol: SYMBOL,
                _earlySweepLockToken: true
            })
        );

        vm.prank(address(factory));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(factory)));
        _govNFT.transferOwnership(address(factory));
    }
}
