// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import "../script/DeployWithTimelock.s.sol";
import "test/utils/BaseTest.sol";

contract DeployWithTimelockTest is BaseTest {
    using stdJson for string;
    using stdStorage for StdStorage;

    address public constant testDeployer = address(1);

    DeployWithTimelock deploy;

    function _setUp() public override {
        deploy = new DeployWithTimelock();

        // Use test account for deployment
        stdstore.target(address(deploy)).sig("deployerAddress()").checked_write(testDeployer);
        vm.deal(testDeployer, TOKEN_10K);
    }

    function test_DeployScript() public {
        deploy.run();

        IGovNFTTimelockFactory factory = deploy.govNFTTimelockFactory();
        assertTrue(address(factory) != address(0));
        assertTrue(factory.govNFT() != address(0));

        GovNFTTimelock govNFT = GovNFTTimelock(factory.govNFT());
        assertTrue(govNFT.artProxy() == address(0)); //TODO change once we set art proxy
        assertEq(govNFT.name(), NAME);
        assertEq(govNFT.symbol(), SYMBOL);
        assertTrue(govNFT.owner() == address(factory));
        assertTrue(factory.govNFTsLength() == 1);
        assertTrue(factory.isGovNFT(address(govNFT)));
        assertTrue(govNFT.factory() == address(factory));
        assertEq(govNFT.timelock(), 0);
        address[] memory govNFTs = factory.govNFTs();
        assertTrue(govNFTs.length == 1);
        assertTrue(govNFTs[0] == address(govNFT));
    }
}
