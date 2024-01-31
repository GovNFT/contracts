// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.20 <0.9.0;

import {MockERC20} from "./MockERC20.sol";
import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/// @dev test governance token adapted from OpenZeppelin's ERC20Votes
contract MockGovernanceToken is MockERC20, Votes {
    error ERC20ExceededSafeSupply(uint256 increasedSupply, uint256 cap);

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 decimals_
    ) MockERC20(name_, symbol_, decimals_) EIP712(name_, "1") {}

    function _maxSupply() internal pure returns (uint256) {
        return type(uint208).max;
    }

    function _update(address from, address to, uint256 value) internal virtual override {
        super._update(from, to, value);
        if (from == address(0)) {
            uint256 supply = totalSupply();
            uint256 cap = _maxSupply();
            if (supply > cap) {
                revert ERC20ExceededSafeSupply(supply, cap);
            }
        }
        _transferVotingUnits(from, to, value);
    }

    function _getVotingUnits(address account) internal view virtual override returns (uint256) {
        return balanceOf(account);
    }

    function numCheckpoints(address account) public view virtual returns (uint32) {
        return _numCheckpoints(account);
    }

    function checkpoints(address account, uint32 pos) public view virtual returns (Checkpoints.Checkpoint208 memory) {
        return _checkpoints(account, pos);
    }
}
