// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract FreezeUnitConcreteTest is BaseTest {
    uint256 public tokenId;
    IGovNFTTimelock public govNFTTimelock;

    function _setUp() public override {
        address vaultImplementation = address(new Vault());
        GovNFTTimelockFactory factory = new GovNFTTimelockFactory({
            _vaultImplementation: vaultImplementation,
            _artProxy: address(artProxy),
            _name: NAME,
            _symbol: SYMBOL,
            _timelock: 1 days
        });
        govNFTTimelock = GovNFTTimelock(factory.govNFT());

        deal(testToken, address(admin), TOKEN_10M);
        admin.approve(testToken, address(govNFTTimelock), TOKEN_10M);
        vm.prank(address(admin));
        tokenId = govNFTTimelock.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_10M,
            _startTime: 0,
            _endTime: WEEK,
            _cliffLength: 0,
            _description: ""
        });
    }

    function test_WhenCallerIsNotAuthorized() external {
        IGovNFTTimelock.Frozen memory frozenStateBefore = govNFTTimelock.frozenState(tokenId);

        // It should revert with ERC721InsufficientApproval
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(this), tokenId)
        );
        govNFTTimelock.freeze({_tokenId: tokenId});

        IGovNFTTimelock.Frozen memory frozenStateAfter = govNFTTimelock.frozenState(tokenId);
        assertEq(frozenStateBefore.isFrozen, frozenStateAfter.isFrozen);
        assertEq(frozenStateBefore.timestamp, frozenStateAfter.timestamp);
    }

    modifier whenCallerIsAuthorized() {
        vm.startPrank(address(recipient));
        _;
    }

    function test_WhenTokenIdIsFrozen() external whenCallerIsAuthorized {
        govNFTTimelock.freeze({_tokenId: tokenId});
        IGovNFTTimelock.Frozen memory frozenState = govNFTTimelock.frozenState(tokenId);
        assertTrue(frozenState.isFrozen);
        assertEq(frozenState.timestamp, block.timestamp);

        // It should revert with AlreadyIntendedFrozen
        vm.expectRevert(IGovNFTTimelock.AlreadyIntendedFrozen.selector);
        govNFTTimelock.freeze({_tokenId: tokenId});

        frozenState = govNFTTimelock.frozenState(tokenId);
        assertTrue(frozenState.isFrozen);
        assertEq(frozenState.timestamp, block.timestamp);
    }

    function test_WhenTokenIdIsNotFrozen() external whenCallerIsAuthorized {
        IGovNFTTimelock.Frozen memory frozenState = govNFTTimelock.frozenState(tokenId);
        assertFalse(frozenState.isFrozen);
        assertEq(frozenState.timestamp, 0);

        // It should emit a {Freeze} event
        vm.expectEmit(address(govNFTTimelock));
        emit IGovNFTTimelock.Freeze({tokenId: tokenId});
        govNFTTimelock.freeze({_tokenId: tokenId});

        frozenState = govNFTTimelock.frozenState(tokenId);
        // It should set isFrozen of _tokenId to true
        assertTrue(frozenState.isFrozen);
        // It should set frozen timestamp of _tokenId to block timestamp
        assertEq(frozenState.timestamp, block.timestamp);
    }
}
