// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract CreateGovNFTUnitConcreteTest is BaseTest {
    address public owner;

    function test_WhenOwnerIsFactory() external {
        owner = address(factory);
        // It should revert with NotAuthorized
        vm.expectRevert(IGovNFTFactory.NotAuthorized.selector);
        factory.createGovNFT({
            _owner: owner,
            _artProxy: address(artProxy),
            _name: NAME,
            _symbol: SYMBOL,
            _earlySweepLockToken: true
        });
    }

    modifier whenOwnerIsNotFactory() {
        owner = address(admin);
        assertNotEq(owner, address(factory));
        _;
    }

    function test_WhenArtProxyIsAddressZero() external whenOwnerIsNotFactory {
        // It should revert with ZeroAddress
        vm.expectRevert(IGovNFTFactory.ZeroAddress.selector);
        factory.createGovNFT({
            _owner: owner,
            _artProxy: address(0),
            _name: NAME,
            _symbol: SYMBOL,
            _earlySweepLockToken: true
        });
    }

    function test_WhenArtProxyIsNotAddressZero() external whenOwnerIsNotFactory {
        // It should emit a {GovNFTTimelockCreated} event
        vm.expectEmit(true, true, false, true, address(factory));
        emit IGovNFTFactory.GovNFTCreated({
            owner: owner,
            artProxy: address(artProxy),
            name: NAME,
            symbol: SYMBOL,
            govNFT: address(0),
            govNFTCount: 3
        });
        address _govNFT = factory.createGovNFT({
            _owner: owner,
            _artProxy: address(artProxy),
            _name: NAME,
            _symbol: SYMBOL,
            _earlySweepLockToken: true
        });

        // It should add new govNFT to registry
        address[] memory govNFTs = factory.govNFTs();
        assertEq(govNFTs.length, 3);
        assertEq(govNFTs[2], _govNFT);
        govNFTs = factory.govNFTs(0, 3);
        assertEq(govNFTs[2], _govNFT);
        assertEq(factory.govNFTByIndex(2), _govNFT);
        assertTrue(factory.isGovNFT(_govNFT));

        govNFT = GovNFT(_govNFT);
        // It should set owner to owner in the new govNFT
        assertEq(govNFT.owner(), owner);
        // It should set artProxy to artProxy in the new govNFT
        assertEq(govNFT.artProxy(), address(artProxy));
        // It should set name to name in the new govNFT
        assertEq(govNFT.name(), NAME);
        // It should set symbol to symbol in the new govNFT
        assertEq(govNFT.symbol(), SYMBOL);
        // It should set earlySweepLockToken to earlySweepLockToken in the new govNFT
        assertTrue(govNFT.earlySweepLockToken());
    }
}
