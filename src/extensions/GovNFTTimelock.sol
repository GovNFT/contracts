// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import {IGovNFTTimelock} from "../interfaces/IGovNFTTimelock.sol";
import {GovNFT} from "../GovNFT.sol";

/// @title Velodrome GovNFTTimelock
/// @author velodrome.finance, @airtoonricardo, @pedrovalido
/// @notice GovNFT implementation that vests ERC-20 tokens to a given address, in the form of an ERC-721
/// @notice Tokens are vested over a determined period of time, as soon as the Cliff period ends
/// @dev    This contract extends the original GovNFT implementation to include a timelock mechanism,
///         in order to separate the splitting functionality in two steps.
contract GovNFTTimelock is GovNFT, IGovNFTTimelock {
    /// @dev Duration of the timelock period
    uint256 public immutable timelock;

    /// @dev tokenId => SplitProposal Proposed Split information
    mapping(uint256 => SplitProposal) internal _proposedSplits;

    constructor(
        address _owner,
        address _artProxy,
        string memory _name,
        string memory _symbol,
        uint256 _timelock
    ) GovNFT(_owner, _artProxy, _name, _symbol) {
        timelock = _timelock;
    }

    /// @inheritdoc IGovNFTTimelock
    function proposedSplits(uint256 _tokenId) external view returns (SplitProposal memory) {
        return _proposedSplits[_tokenId];
    }

    /// @inheritdoc IGovNFTTimelock
    function commitSplit(uint256 _from, SplitParams[] calldata _paramsList) external nonReentrant {
        _checkAuthorized({owner: _ownerOf(_from), spender: msg.sender, tokenId: _from});

        // Fetch Parent Lock
        Lock memory parentLock = locks[_from];
        uint256 totalVested = _totalVested(_from);
        _validateSplitParams({_parentLock: parentLock, _parentTotalVested: totalVested, _paramsList: _paramsList});

        // Clear any previously proposed Splits
        SplitProposal storage splitProposal = _proposedSplits[_from];
        delete splitProposal.pendingSplits;

        // Store new Split Proposal
        SplitParams memory params;
        uint256 length = _paramsList.length;
        for (uint256 i = 0; i < length; i++) {
            params = _paramsList[i];
            splitProposal.pendingSplits.push(params);
            emit CommitSplit({
                from: _from,
                recipient: params.beneficiary,
                splitAmount: params.amount,
                startTime: params.start,
                endTime: params.end
            });
        }
        splitProposal.timestamp = block.timestamp;
    }

    /// @inheritdoc IGovNFTTimelock
    function finalizeSplit(uint256 _from) external virtual nonReentrant returns (uint256[] memory _splitTokenIds) {
        _checkAuthorized({owner: _ownerOf(_from), spender: msg.sender, tokenId: _from});
        SplitProposal memory splitProposal = _proposedSplits[_from];
        if (block.timestamp < splitProposal.timestamp + timelock) revert SplitTooSoon();

        uint256 sum;
        uint256 splitCliffEnd;
        SplitParams memory params;
        uint256 length = splitProposal.pendingSplits.length;
        _splitTokenIds = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            params = splitProposal.pendingSplits[i];

            // Update Split Proposal's timestamps if proposed `start` is in past
            if (block.timestamp > params.start) {
                splitCliffEnd = params.start + params.cliff;
                params.start = block.timestamp;
                params.cliff = block.timestamp < splitCliffEnd ? splitCliffEnd - block.timestamp : 0;
            }
            sum += params.amount;
        }

        // Fetch Parent Lock
        Lock memory parentLock = locks[_from];
        uint256 totalVested = _totalVested(_from);
        if (parentLock.totalLocked - totalVested < sum) revert AmountTooBig();

        // Execute all proposed Splits for `_from`
        _splitTokenIds = _split({
            _from: _from,
            _parentTotalVested: totalVested,
            _parentLock: parentLock,
            _paramsList: splitProposal.pendingSplits
        });

        delete _proposedSplits[_from];
    }

    function _update(address _to, uint256 _tokenId, address _auth) internal virtual override returns (address) {
        // Clear any previously proposed Splits
        delete _proposedSplits[_tokenId];
        return super._update(_to, _tokenId, _auth);
    }
}
