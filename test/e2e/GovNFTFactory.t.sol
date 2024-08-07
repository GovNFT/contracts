// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract GovNFTFactoryTest is BaseTest {
    function _setUp() public override {
        factory = new GovNFTFactory({
            _vaultImplementation: vaultImplementation,
            _artProxy: address(artProxy),
            _name: NAME,
            _symbol: SYMBOL
        });
    }

    function test_Setup() public {
        assertFalse(factory.vaultImplementation() == address(0));
        assertFalse(factory.govNFT() == address(0));
        uint256 length = factory.govNFTsLength();
        assertEq(length, 1);
        assertTrue(factory.isGovNFT(factory.govNFT()));

        address[] memory govNFTs = factory.govNFTs(0, length);
        GovNFT _govNFT = GovNFT(govNFTs[0]);
        assertEq(govNFTs.length, 1);
        assertEq(address(_govNFT), factory.govNFT());
        assertEq(address(_govNFT), factory.govNFTByIndex(0));

        assertEq(_govNFT.name(), NAME);
        assertEq(_govNFT.symbol(), SYMBOL);
        assertFalse(_govNFT.earlySweepLockToken());
        assertEq(_govNFT.owner(), address(factory));
        assertEq(_govNFT.vaultImplementation(), factory.vaultImplementation());
    }

    function test_CreateGovNFT() public {
        address customArtProxy = vm.addr(0x54321);
        assertEq(factory.govNFTsLength(), 1);

        GovNFT _govNFT = GovNFT(
            factory.createGovNFT({
                _owner: address(admin),
                _artProxy: customArtProxy,
                _name: "CustomGovNFT",
                _symbol: "CustomGovNFT",
                _earlySweepLockToken: true
            })
        );
        uint256 length = factory.govNFTsLength();
        assertEq(length, 2);
        address[] memory govNFTs = factory.govNFTs(0, length);
        assertEq(govNFTs.length, 2);
        assertEq(govNFTs[1], address(_govNFT));
        assertEq(factory.govNFTByIndex(1), address(_govNFT));

        assertEq(_govNFT.name(), "CustomGovNFT");
        assertEq(_govNFT.symbol(), "CustomGovNFT");
        assertEq(_govNFT.owner(), address(admin));
        assertEq(_govNFT.artProxy(), customArtProxy);
        assertEq(_govNFT.vaultImplementation(), factory.vaultImplementation());
        assertTrue(_govNFT.earlySweepLockToken());
    }

    function testFuzz_CreateMultipleGovNFTs(uint8 govNFTCount) public {
        assertEq(factory.govNFTsLength(), 1);
        address[] memory govNFTs = new address[](govNFTCount);
        for (uint256 i = 0; i < govNFTCount; i++) {
            govNFTs[i] = factory.createGovNFT({
                _owner: address(admin),
                _artProxy: vm.addr(0x54321),
                _name: "CustomGovNFT",
                _symbol: "CustomGovNFT",
                _earlySweepLockToken: true
            });
        }
        uint256 length = factory.govNFTsLength();
        // increment by 1 to account for existing permissionless GovNFT
        assertEq(length, uint256(govNFTCount) + 1);
        address[] memory fetchedGovNFTs = factory.govNFTs(1, length);
        for (uint256 i = 0; i < govNFTCount; i++) {
            assertEq(fetchedGovNFTs[i], govNFTs[i]);
            // account for permissionless govNFT in index 0
            assertEq(factory.govNFTByIndex(i + 1), govNFTs[i]);
        }
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
        GovNFT _govNFT = GovNFT(
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
        GovNFT _govNFT = GovNFT(factory.govNFT());
        assertEq(_govNFT.owner(), address(factory));

        vm.prank(address(notAdmin));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(notAdmin)));
        _govNFT.transferOwnership(address(notAdmin));

        vm.prank(address(admin));
        _govNFT = GovNFT(
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
