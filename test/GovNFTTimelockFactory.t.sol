// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract GovNFTTimelockFactoryTest is BaseTest {
    IGovNFTTimelockFactory factory;
    address public artProxy = vm.addr(0x12345);
    uint256 public timelock = 0; //TODO: set timelock

    function _setUp() public override {
        factory = new GovNFTTimelockFactory({_artProxy: artProxy, _name: NAME, _symbol: SYMBOL, _timelock: timelock});
    }

    function test_Setup() public {
        assertFalse(factory.govNFT() == address(0));
        assertEq(factory.govNFTsLength(), 1);
        assertTrue(factory.isGovNFT(factory.govNFT()));

        address[] memory govNFTs = factory.govNFTs();
        GovNFTTimelock _govNFT = GovNFTTimelock(govNFTs[0]);
        assertEq(govNFTs.length, 1);
        assertEq(address(_govNFT), factory.govNFT());

        assertEq(_govNFT.name(), NAME);
        assertEq(_govNFT.symbol(), SYMBOL);
        assertFalse(_govNFT.earlySweepLockToken());
        assertEq(_govNFT.owner(), address(factory));
        assertEq(_govNFT.timelock(), timelock);
    }

    function test_RevertIf_CreateWithFactoryAsAdmin() public {
        vm.expectRevert(IGovNFTTimelockFactory.NotAuthorized.selector);
        factory.createGovNFT({
            _owner: address(factory),
            _artProxy: address(0),
            _name: NAME,
            _symbol: SYMBOL,
            _earlySweepLockToken: true,
            _timelock: timelock
        });
    }

    function test_CreateGovNFT() public {
        address customArtProxy = vm.addr(0x54321);
        assertEq(factory.govNFTsLength(), 1);

        GovNFTTimelock _govNFT = GovNFTTimelock(
            factory.createGovNFT({
                _owner: address(admin),
                _artProxy: customArtProxy,
                _name: "CustomGovNFTTimelock",
                _symbol: "CustomGovNFT",
                _earlySweepLockToken: true,
                _timelock: timelock
            })
        );
        assertEq(factory.govNFTsLength(), 2);
        address[] memory govNFTs = factory.govNFTs();
        assertEq(govNFTs.length, 2);
        assertTrue(govNFTs[1] == address(_govNFT));

        assertEq(_govNFT.name(), "CustomGovNFTTimelock");
        assertEq(_govNFT.symbol(), "CustomGovNFT");
        assertEq(_govNFT.owner(), address(admin));
        assertEq(_govNFT.artProxy(), customArtProxy);
        assertTrue(_govNFT.earlySweepLockToken());
        assertEq(_govNFT.timelock(), timelock);
    }

    function test_CanCreateLockIfNotOwnerInPermissionlessGovNFT() public {
        IGovNFT _govNFT = IGovNFT(factory.govNFT());

        admin.approve(testToken, address(_govNFT), TOKEN_100K);
        vm.prank(address(admin));
        _govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            uint40(block.timestamp),
            uint40(block.timestamp) + WEEK * 2,
            WEEK
        );
        notAdmin.approve(testToken, address(_govNFT), TOKEN_100K);
        vm.prank(address(notAdmin));
        _govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            uint40(block.timestamp),
            uint40(block.timestamp) + WEEK * 2,
            WEEK
        );
    }

    function test_RevertIf_CreateLockIfNotOwner() public {
        IGovNFT _govNFT = IGovNFT(
            factory.createGovNFT({
                _owner: address(admin),
                _artProxy: artProxy,
                _name: NAME,
                _symbol: SYMBOL,
                _earlySweepLockToken: true,
                _timelock: timelock
            })
        );

        admin.approve(testToken, address(_govNFT), TOKEN_100K);
        vm.prank(address(admin));
        _govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            uint40(block.timestamp),
            uint40(block.timestamp) + WEEK * 2,
            WEEK
        );
        notAdmin.approve(testToken, address(_govNFT), TOKEN_100K);
        vm.prank(address(notAdmin));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(notAdmin)));
        _govNFT.createLock(
            testToken,
            address(recipient),
            TOKEN_100K,
            uint40(block.timestamp),
            uint40(block.timestamp) + WEEK * 2,
            WEEK
        );
    }
}
