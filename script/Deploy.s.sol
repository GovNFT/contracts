// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import {GovNFTFactory} from "src/GovNFTFactory.sol";

contract Deploy is Script {
    using stdJson for string;

    uint256 public deployPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
    address public deployerAddress = vm.rememberKey(deployPrivateKey);
    string public outputFilename = vm.envString("OUTPUT_FILENAME");

    GovNFTFactory public govNFTFactory;
    string public jsonOutput;

    function run() public {
        vm.startBroadcast(deployerAddress);
        //TODO choose veartproxy
        govNFTFactory = new GovNFTFactory(
            address(0),
            "GovNFT: NFT for vested distribution of (governance) tokens",
            "GOVNFT"
        );
        vm.stopBroadcast();

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/constants/output/");
        path = string.concat(path, outputFilename);
        vm.writeJson(vm.serializeAddress("", "GovNFTFactory", address(govNFTFactory)), path);
    }
}
