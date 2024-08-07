// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import {MockERC20} from "./MockERC20.sol";

/// @dev MockFeeERC20 contract for testing use only
contract MockFeeERC20 is MockERC20 {
    mapping(address => bool) public feeWhitelist;

    constructor(string memory name_, string memory symbol_, uint256 decimals_) MockERC20(name_, symbol_, decimals_) {}

    function setFeeWhitelist(address account, bool allow) public {
        feeWhitelist[account] = allow;
    }

    function transferFrom(address from, address to, uint256 value) public virtual override returns (bool) {
        return super.transferFrom(from, to, feeWhitelist[msg.sender] ? value : (value * 9) / 10);
    }

    function transfer(address to, uint256 value) public virtual override returns (bool) {
        return super.transfer(to, feeWhitelist[msg.sender] ? value : (value * 9) / 10);
    }
}
