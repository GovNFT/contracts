// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import "./handler/GovNFTSplitHandlerV2.sol";
import "test/invariants/GovNFTInvariants.sol";
import {GovNFTFactory} from "src/GovNFTFactory.sol";

contract GovNFTSplitInvariantV2Test is GovNFTInvariants {
    function _setUp() internal virtual override {
        GovNFTFactory factory = new GovNFTFactory({_artProxy: vm.addr(0x12345), _name: NAME, _symbol: SYMBOL});
        govNFT = IGovNFT(factory.govNFT());

        handler = new GovNFTSplitHandlerV2({
            _govNFT: GovNFTSplit(address(govNFT)),
            _timestore: timestore,
            _testToken: testToken,
            _airdropToken: airdropToken,
            _testActorCount: 10,
            _initialDeposit: 1e27, // 1e9 = 1B tokens with 18 decimals
            _maxLocks: 5
        });
    }
}
