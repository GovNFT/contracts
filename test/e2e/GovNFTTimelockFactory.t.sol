// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract GovNFTTimelockFactoryTest is BaseTest {
    IGovNFTTimelockFactory factoryLock;
    uint256 public timelock = 1 hours;

    function _setUp() public override {
        factoryLock = new GovNFTTimelockFactory({
            _vaultImplementation: vaultImplementation,
            _artProxy: address(artProxy),
            _name: NAME,
            _symbol: SYMBOL,
            _timelock: timelock
        });
    }

    function test_Setup() public {
        assertFalse(factoryLock.vaultImplementation() == address(0));
        assertFalse(factoryLock.govNFT() == address(0));
        uint256 length = factoryLock.govNFTsLength();
        assertEq(length, 1);
        assertTrue(factoryLock.isGovNFT(factoryLock.govNFT()));

        address[] memory govNFTs = factoryLock.govNFTs(0, length);
        GovNFTTimelock _govNFT = GovNFTTimelock(govNFTs[0]);
        assertEq(govNFTs.length, 1);
        assertEq(address(_govNFT), factoryLock.govNFT());
        assertEq(address(_govNFT), factoryLock.govNFTByIndex(0));

        assertEq(_govNFT.name(), NAME);
        assertEq(_govNFT.symbol(), SYMBOL);
        assertFalse(_govNFT.earlySweepLockToken());
        assertEq(_govNFT.owner(), address(factoryLock));
        assertEq(_govNFT.vaultImplementation(), factoryLock.vaultImplementation());
        assertEq(_govNFT.timelock(), timelock);
    }

    function testFuzz_CreateMultipleGovNFTs(uint8 govNFTCount) public {
        assertEq(factoryLock.govNFTsLength(), 1);
        address[] memory govNFTs = new address[](govNFTCount);
        for (uint256 i = 0; i < govNFTCount; i++) {
            govNFTs[i] = factoryLock.createGovNFT({
                _owner: address(admin),
                _artProxy: vm.addr(0x54321),
                _name: "CustomGovNFTTimelock",
                _symbol: "CustomGovNFT",
                _earlySweepLockToken: true,
                _timelock: timelock
            });
        }
        uint256 length = factoryLock.govNFTsLength();
        // increment by 1 to account for existing permissionless GovNFT
        assertEq(length, uint256(govNFTCount) + 1);
        address[] memory fetchedGovNFTs = factoryLock.govNFTs(1, length);
        for (uint256 i = 0; i < govNFTCount; i++) {
            assertEq(fetchedGovNFTs[i], govNFTs[i]);
            // account for permissionless govNFT in index 0
            assertEq(factoryLock.govNFTByIndex(i + 1), govNFTs[i]);
        }
    }

    function test_CanCreateLockIfNotOwnerInPermissionlessGovNFT() public {
        IGovNFT _govNFT = IGovNFT(factoryLock.govNFT());

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
}
