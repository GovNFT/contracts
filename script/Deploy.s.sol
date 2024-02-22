// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import {GovNFTSplit} from "src/extensions/GovNFTSplit.sol";

contract Deploy is Script {
    using stdJson for string;

    uint256 public deployPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
    address public deployerAddress = vm.rememberKey(deployPrivateKey);
    string public outputFilename = vm.envString("OUTPUT_FILENAME");

    GovNFTSplit public govNFT;
    string public jsonOutput;

    function run() public {
        vm.startBroadcast(deployerAddress);
        govNFT = new GovNFTSplit();
        vm.stopBroadcast();

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/constants/output/");
        path = string.concat(path, outputFilename);
        vm.writeJson(vm.serializeAddress("", "GovNFT", address(govNFT)), path);
    }
}
