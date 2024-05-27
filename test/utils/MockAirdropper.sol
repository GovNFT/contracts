// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @dev test aidrops that require action
contract MockAirdropper {
    using SafeERC20 for IERC20;

    address public airdropToken;
    address public airdropReceiver;
    uint256 public airdropAmount;

    error OnlyAirdropReceiver();

    constructor(address _airdropToken, uint256 _airdropAmount, address _airdropReceiver) {
        airdropToken = _airdropToken;
        airdropAmount = _airdropAmount;
        airdropReceiver = _airdropReceiver;
    }

    function claimAirdrop() public {
        if (msg.sender != airdropReceiver) {
            revert OnlyAirdropReceiver();
        }
        IERC20(airdropToken).safeTransfer(airdropReceiver, airdropAmount);
    }
}
