// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "../../script/Deploy.s.sol";
import "test/utils/BaseTest.sol";

contract DeployTest is BaseTest {
    using stdJson for string;
    using stdStorage for StdStorage;

    address public constant testDeployer = address(1);

    Deploy deploy;

    function _setUp() public override {
        deploy = new Deploy();

        // Use test account for deployment
        stdstore.target(address(deploy)).sig("deployerAddress()").checked_write(testDeployer);
        vm.deal(testDeployer, TOKEN_10K);
    }

    function test_DeployScript() public {
        deploy.run();

        IGovNFTFactory factory = deploy.govNFTFactory();
        assertTrue(address(factory) != address(0));
        assertTrue(factory.govNFT() != address(0));

        GovNFTSplit govNFT = GovNFTSplit(factory.govNFT());
        assertTrue(govNFT.artProxy() == address(0)); //TODO change once we set art proxy
        assertEq(govNFT.name(), NAME);
        assertEq(govNFT.symbol(), SYMBOL);
        assertTrue(govNFT.owner() == address(factory));
        uint256 length = factory.govNFTsLength();
        assertTrue(length == 1);
        assertTrue(factory.isGovNFT(address(govNFT)));
        assertTrue(govNFT.factory() == address(factory));
        address[] memory govNFTs = factory.govNFTs(0, length);
        assertTrue(govNFTs.length == 1);
        assertTrue(govNFTs[0] == address(govNFT));
    }
}
