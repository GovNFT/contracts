// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import "src/GovNFT.sol";
import "forge-std/Test.sol";
import "forge-std/StdJson.sol";
import "../script/Deploy.s.sol";
import {BaseTest} from "test/utils/BaseTest.sol";
import {IGovNFTFactory} from "src/interfaces/IGovNFTFactory.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract TestDeploy is BaseTest {
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

    function testDeployScript() public {
        deploy.run();

        IGovNFTFactory factory = deploy.govNFTFactory();
        assertTrue(address(factory) != address(0));
        assertTrue(factory.govNFT() != address(0));

        IGovNFT govNFT = IGovNFT(factory.govNFT());
        assertTrue(govNFT.artProxy() == address(0)); //TODO change once we set art proxy
        assertEq(ERC721(address(govNFT)).name(), "GovNFT");
        assertEq(ERC721(address(govNFT)).symbol(), "GovNFT");
        assertTrue(Ownable(address(govNFT)).owner() == address(factory));
        assertTrue(factory.govNFTsLength() == 1);
        assertTrue(factory.isGovNFT(address(govNFT)));
        assertTrue(govNFT.factory() == address(factory));
        address[] memory govNFTs = factory.govNFTs();
        assertTrue(govNFTs.length == 1);
        assertTrue(govNFTs[0] == address(govNFT));
    }
}
