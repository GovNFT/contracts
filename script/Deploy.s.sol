// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";

import {GovNFTFactory} from "src/GovNFTFactory.sol";
import {ArtProxy} from "src/art/ArtProxy.sol";

contract Deploy is Script {
    using stdJson for string;

    uint256 public deployPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
    address public deployerAddress = vm.rememberKey(deployPrivateKey);
    string public outputFilename = vm.envString("OUTPUT_FILENAME");

    GovNFTFactory public govNFTFactory;
    ArtProxy public artProxy;
    string public jsonOutput;

    function run() public {
        vm.startBroadcast(deployerAddress);
        artProxy = new ArtProxy();
        govNFTFactory = new GovNFTFactory({
            _artProxy: address(artProxy),
            _name: "GovNFT: NFT for vested distribution of (governance) tokens",
            _symbol: "GOVNFT"
        });
        vm.stopBroadcast();

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/constants/output/");
        path = string.concat(path, outputFilename);
        vm.writeJson(vm.serializeAddress("", "GovNFTFactory", address(govNFTFactory)), path);
        vm.writeJson(vm.serializeAddress("", "ArtProxy", address(artProxy)), path);
    }
}
