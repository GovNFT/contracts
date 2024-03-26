// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IVault} from "./interfaces/IVault.sol";

/// @title Vault (for GovNFT locks)
/// @notice Vault that stores the ERC-20 tokens of a lock.
/// @notice Funds from each lock are stored in each Vault to allow delegation of locked governance tokens.
contract Vault is IVault, Ownable {
    using SafeERC20 for IERC20;

    /// @inheritdoc IVault
    address public immutable token;

    constructor(address _token) Ownable(msg.sender) {
        token = _token;
    }

    /// @inheritdoc IVault
    function withdraw(address _recipient, uint256 _amount) external onlyOwner {
        IERC20(token).safeTransfer(_recipient, _amount);
    }

    /// @inheritdoc IVault
    function delegate(address _delegatee) external onlyOwner {
        IVotes(token).delegate(_delegatee);
    }

    /// @inheritdoc IVault
    function sweep(address _token, address _recipient, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(_recipient, _amount);
    }
}
