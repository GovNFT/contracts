// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import {IGovNFTSplit} from "../interfaces/IGovNFTSplit.sol";
import {GovNFT} from "../GovNFT.sol";

/// @title Velodrome GovNFTSplit
/// @author velodrome.finance, @airtoonricardo, @pedrovalido
/// @notice GovNFT implementation that vests ERC-20 tokens to a given address, in the form of an ERC-721
/// @notice Tokens are vested over a determined period of time, as soon as the Cliff period ends
/// @dev    This contract extends the original GovNFT implementation to include Splitting functionality
contract GovNFTSplit is GovNFT, IGovNFTSplit {
    constructor(
        address _owner,
        address _artProxy,
        string memory _name,
        string memory _symbol
    ) GovNFT(_owner, _artProxy, _name, _symbol) {}

    /// @inheritdoc IGovNFTSplit
    function split(uint256 _from, SplitParams[] calldata _paramsList) external nonReentrant returns (uint256[] memory) {
        _checkAuthorized({owner: _ownerOf(_from), spender: msg.sender, tokenId: _from});

        // Fetch Parent Lock
        Lock storage parentLock = _locks[_from];
        uint256 totalVested = _totalVested(parentLock);
        _validateSplitParams({_parentLock: parentLock, _parentTotalVested: totalVested, _paramsList: _paramsList});

        return
            _split({_from: _from, _parentTotalVested: totalVested, _parentLock: parentLock, _paramsList: _paramsList});
    }
}
