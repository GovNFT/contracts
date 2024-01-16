// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "./interfaces/IVault.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/// @title Velodrome Vault (for VestingEscrow grants)
/// @author velodrome.finance, @airtoonricardo, @pedrovalido
/// @notice Vault that stores the ERC-20 tokens of a grant.
/// @notice Funds from each grant are stored in each Vault to allow delegation of locked governance tokens.
contract Vault is IVault, Ownable {
    using SafeERC20 for IERC20;

    address public token;

    constructor(address _token) Ownable(msg.sender) {
        token = _token;
    }

    /// @inheritdoc IVault
    function withdraw(address receiver, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(receiver, amount);
    }

    /// @inheritdoc IVault
    function delegate(address delegatee) external onlyOwner {
        IVotes(token).delegate(delegatee);
    }

    /// @inheritdoc IVault
    function sweep(address _token, address recipient, uint256 amount) external onlyOwner {
        IERC20(_token).safeTransfer(recipient, amount);
    }
}
