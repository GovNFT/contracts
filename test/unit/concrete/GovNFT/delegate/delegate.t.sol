// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract DelegateUnitConcreteTest is BaseTest {
    address public testAddr;
    uint256 public tokenId;

    function _setUp() public override {
        testAddr = makeAddr("alice");
        admin.approve(testGovernanceToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        tokenId = govNFT.createLock({
            _token: testGovernanceToken,
            _recipient: address(admin),
            _amount: TOKEN_100K,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 2,
            _cliffLength: WEEK,
            _description: ""
        });
    }

    function test_WhenCallerIsNotAuthorized() external {
        // It should revert with OwnableUnauthorizedAccount
        vm.expectRevert(
            abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(this), tokenId)
        );
        govNFT.delegate({_tokenId: tokenId, _delegatee: testAddr});
    }

    modifier whenCallerIsAuthorized() {
        vm.startPrank(address(admin));
        _;
    }

    function test_RevertWhen_LockTokenDoesNotSupportDelegation() external whenCallerIsAuthorized {
        // It should revert
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        tokenId = govNFT.createLock({
            _token: testToken,
            _recipient: address(admin),
            _amount: TOKEN_100K,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 2,
            _cliffLength: WEEK,
            _description: ""
        });
        vm.expectRevert();
        govNFT.delegate({_tokenId: tokenId, _delegatee: testAddr});
    }

    function test_WhenLockTokenSupportsDelegation() external whenCallerIsAuthorized {
        // It should set lock's delegatee
        // It should emit a {Delegate} event
        address vault = govNFT.locks(tokenId).vault;
        assertEq(IVotes(testGovernanceToken).delegates(address(recipient)), address(0));
        assertEq(IVotes(testGovernanceToken).delegates(address(admin)), address(0));
        assertEq(IVotes(testGovernanceToken).delegates(vault), address(0));

        assertEq(IVotes(testGovernanceToken).getVotes(testAddr), 0);

        vm.expectEmit(address(govNFT));
        emit IGovNFT.Delegate({tokenId: tokenId, delegate: testAddr});
        govNFT.delegate({_tokenId: tokenId, _delegatee: testAddr});

        assertEq(IVotes(testGovernanceToken).delegates(address(recipient)), address(0));
        assertEq(IVotes(testGovernanceToken).delegates(address(admin)), address(0));
        assertEq(IVotes(testGovernanceToken).delegates(vault), testAddr);

        assertEq(IVotes(testGovernanceToken).getVotes(testAddr), TOKEN_100K);
    }
}
