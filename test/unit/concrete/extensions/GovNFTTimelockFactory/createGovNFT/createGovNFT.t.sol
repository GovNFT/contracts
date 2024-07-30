// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract CreateGovNFTTimelockUnitConcreteTest is BaseTest {
    address public owner;
    IGovNFTTimelockFactory public timelockFactory;
    GovNFTTimelock public govNFTTimelock;

    function _setUp() public override {
        vm.prank(address(admin));
        vaultImplementation = address(new Vault());
        timelockFactory = new GovNFTTimelockFactory({
            _vaultImplementation: vaultImplementation,
            _artProxy: address(artProxy),
            _name: NAME,
            _symbol: SYMBOL,
            _timelock: 1 days
        });
    }

    function test_WhenOwnerIsFactory() external {
        owner = address(timelockFactory);
        // It should revert with NotAuthorized
        vm.expectRevert(IGovNFTFactory.NotAuthorized.selector);
        timelockFactory.createGovNFT({
            _owner: owner,
            _artProxy: address(artProxy),
            _name: NAME,
            _symbol: SYMBOL,
            _earlySweepLockToken: true,
            _timelock: 1 days
        });
    }

    modifier whenOwnerIsNotFactory() {
        owner = address(admin);
        assertNotEq(owner, address(timelockFactory));
        _;
    }

    function test_WhenArtProxyIsAddressZero() external whenOwnerIsNotFactory {
        // It should revert with ZeroAddress
        vm.expectRevert(IGovNFTFactory.ZeroAddress.selector);
        timelockFactory.createGovNFT({
            _owner: owner,
            _artProxy: address(0),
            _name: NAME,
            _symbol: SYMBOL,
            _earlySweepLockToken: true,
            _timelock: 1 days
        });
    }

    function test_WhenArtProxyIsNotAddressZero() external whenOwnerIsNotFactory {
        // It should emit a {GovNFTTimelockCreated} event
        vm.expectEmit(true, true, false, true, address(timelockFactory));
        emit IGovNFTTimelockFactory.GovNFTTimelockCreated({
            owner: owner,
            artProxy: address(artProxy),
            name: NAME,
            symbol: SYMBOL,
            timelock: 1 days,
            govNFT: address(0),
            govNFTCount: 2
        });
        address _govNFT = timelockFactory.createGovNFT({
            _owner: owner,
            _artProxy: address(artProxy),
            _name: NAME,
            _symbol: SYMBOL,
            _earlySweepLockToken: true,
            _timelock: 1 days
        });

        // It should add new govNFT to registry
        address[] memory govNFTs = timelockFactory.govNFTs();
        assertEq(govNFTs.length, 2);
        assertEq(govNFTs[1], _govNFT);
        govNFTs = timelockFactory.govNFTs(0, 2);
        assertEq(govNFTs[1], _govNFT);
        assertEq(timelockFactory.govNFTByIndex(1), _govNFT);
        assertTrue(timelockFactory.isGovNFT(_govNFT));

        govNFTTimelock = GovNFTTimelock(_govNFT);
        // It should set owner to owner in the new govNFT
        assertEq(govNFTTimelock.owner(), owner);
        // It should set artProxy to artProxy in the new govNFT
        assertEq(govNFTTimelock.artProxy(), address(artProxy));
        // It should set name to name in the new govNFT
        assertEq(govNFTTimelock.name(), NAME);
        // It should set symbol to symbol in the new govNFT
        assertEq(govNFTTimelock.symbol(), SYMBOL);
        // It should set earlySweepLockToken to earlySweepLockToken in the new govNFT
        assertTrue(govNFTTimelock.earlySweepLockToken());
        // It should set timelock to timelock in the new govNFT
        assertEq(govNFTTimelock.timelock(), 1 days);
    }
}
