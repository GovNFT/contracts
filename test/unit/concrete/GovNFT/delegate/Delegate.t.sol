// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "test/utils/BaseTest.sol";

contract DelegateTest is BaseTest {
    address public testAddr;
    uint256 public tokenId;

    function _setUp() public override {
        testAddr = makeAddr("alice");
        admin.approve(testGovernanceToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        tokenId = govNFT.createLock({
            _token: testGovernanceToken,
            _recipient: address(recipient),
            _amount: TOKEN_100K,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 2,
            _cliffLength: WEEK,
            _description: ""
        });
    }

    function test_Delegate() public {
        IGovNFT.Lock memory lock = govNFT.locks(tokenId);
        assertEq(IVotes(testGovernanceToken).delegates(address(recipient)), address(0));
        assertEq(IVotes(testGovernanceToken).delegates(address(admin)), address(0));
        assertEq(IVotes(testGovernanceToken).delegates(lock.vault), address(0));

        assertEq(IVotes(testGovernanceToken).getVotes(testAddr), 0);

        vm.expectEmit(true, true, false, true, address(govNFT));
        emit IGovNFT.Delegate({tokenId: tokenId, delegate: testAddr});
        vm.prank(address(recipient));
        govNFT.delegate(tokenId, testAddr);

        assertEq(IVotes(testGovernanceToken).delegates(lock.vault), testAddr);

        assertEq(IVotes(testGovernanceToken).delegates(address(recipient)), address(0));
        assertEq(IVotes(testGovernanceToken).delegates(address(admin)), address(0));
        assertEq(IVotes(testGovernanceToken).delegates(lock.vault), testAddr);

        assertEq(IVotes(testGovernanceToken).getVotes(testAddr), TOKEN_100K);
    }

    function test_DelegateCoupleGrantsWithSameToken() public {
        address recipient1 = address(recipient);
        address recipient2 = makeAddr("recipient2");
        deal(testGovernanceToken, address(admin), TOKEN_100K);
        admin.approve(testGovernanceToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        uint256 tokenId2 = govNFT.createLock({
            _token: testGovernanceToken,
            _recipient: recipient2,
            _amount: TOKEN_100K,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 2,
            _cliffLength: WEEK,
            _description: ""
        });

        assertEq(IVotes(testGovernanceToken).delegates(address(admin)), address(0));
        assertEq(IVotes(testGovernanceToken).delegates(recipient1), address(0));
        assertEq(IVotes(testGovernanceToken).delegates(recipient2), address(0));

        assertEq(IVotes(testGovernanceToken).getVotes(address(admin)), 0);
        assertEq(IVotes(testGovernanceToken).getVotes(recipient1), 0);
        assertEq(IVotes(testGovernanceToken).getVotes(recipient2), 0);

        vm.prank(recipient1);
        govNFT.delegate(tokenId, recipient1);

        vm.prank(recipient2);
        govNFT.delegate(tokenId2, recipient2);

        assertEq(IVotes(testGovernanceToken).getVotes(address(admin)), 0);
        assertEq(IVotes(testGovernanceToken).getVotes(recipient1), TOKEN_100K);
        assertEq(IVotes(testGovernanceToken).getVotes(recipient2), TOKEN_100K);

        vm.prank(recipient1);
        govNFT.delegate(tokenId, recipient2);

        assertEq(IVotes(testGovernanceToken).getVotes(address(admin)), 0);
        assertEq(IVotes(testGovernanceToken).getVotes(recipient1), 0);
        assertEq(IVotes(testGovernanceToken).getVotes(recipient2), 2 * TOKEN_100K);
    }

    function test_RevertIf_DelegateWithTokenNotSupported() public {
        admin.approve(testToken, address(govNFT), TOKEN_100K);
        vm.prank(address(admin));
        tokenId = govNFT.createLock({
            _token: testToken,
            _recipient: address(recipient),
            _amount: TOKEN_100K,
            _startTime: uint40(block.timestamp),
            _endTime: uint40(block.timestamp) + WEEK * 2,
            _cliffLength: WEEK,
            _description: ""
        });
        vm.expectRevert();
        vm.prank(address(recipient));
        govNFT.delegate(tokenId, testAddr);
    }

    function test_RevertIf_DelegateIfNotRecipient() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, testAddr, tokenId));
        vm.prank(address(testAddr));
        govNFT.delegate(tokenId, testAddr);
    }
}
