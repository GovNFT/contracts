// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract TimelockTransferUnitConcreteTest is BaseTest {
    uint256 public tokenId;
    uint256 public timelock = 1 days;
    IGovNFTTimelock public govNFTTimelock;
    address public govnftTimelockRecipient = makeAddr("alice");

    function _setUp() public override {
        address vaultImplementation = address(new Vault());
        GovNFTTimelockFactory factory = new GovNFTTimelockFactory({
            _vaultImplementation: vaultImplementation,
            _artProxy: address(artProxy),
            _name: NAME,
            _symbol: SYMBOL,
            _timelock: timelock
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

    function test_GivenLockToTransferIsNotFrozen() external {
        IGovNFTTimelock.Frozen memory frozen = govNFTTimelock.frozenState(tokenId);
        assertEq(frozen.isFrozen, false);

        vm.prank(address(recipient));
        // It should revert with UnfrozenToken
        vm.expectRevert(IGovNFTTimelock.UnfrozenToken.selector);
        IERC721(address(govNFTTimelock)).safeTransferFrom(address(recipient), govnftTimelockRecipient, tokenId);
    }

    modifier givenLockToTransferIsFrozen() {
        vm.prank(address(recipient));
        govNFTTimelock.freeze(tokenId);

        IGovNFTTimelock.Frozen memory frozen = govNFTTimelock.frozenState(tokenId);
        assertEq(frozen.isFrozen, true);
        assertEq(frozen.timestamp, block.timestamp);
        _;
    }

    function test_GivenTimelockPeriodNotPassed() external givenLockToTransferIsFrozen {
        IGovNFTTimelock.Frozen memory frozen = govNFTTimelock.frozenState(tokenId);
        assertGt(frozen.timestamp + timelock, block.timestamp);

        vm.prank(address(recipient));
        // It should revert with UnfrozenToken
        vm.expectRevert(IGovNFTTimelock.UnfrozenToken.selector);
        IERC721(address(govNFTTimelock)).safeTransferFrom(address(recipient), govnftTimelockRecipient, tokenId);
    }

    function test_GivenTimelockPeriodPassed() external givenLockToTransferIsFrozen {
        skip(timelock);
        IGovNFTTimelock.Frozen memory frozen = govNFTTimelock.frozenState(tokenId);
        assertLe(frozen.timestamp + timelock, block.timestamp);

        assertEq(govNFTTimelock.ownerOf(tokenId), address(recipient));

        vm.prank(address(recipient));

        // It should emit {Transfer}
        vm.expectEmit(address(govNFTTimelock));
        emit IERC721.Transfer(address(recipient), govnftTimelockRecipient, tokenId);
        IERC721(address(govNFTTimelock)).safeTransferFrom(address(recipient), govnftTimelockRecipient, tokenId);

        // It should execute transfer
        assertEq(govNFTTimelock.ownerOf(tokenId), govnftTimelockRecipient);

        frozen = govNFTTimelock.frozenState(tokenId);
        // It should set the frozen state to false
        assertEq(frozen.isFrozen, false);

        // It should set the frozen state timestamp to 0
        assertEq(frozen.timestamp, 0);
    }
}
