// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestOwner {
    function approve(address _token, address _spender, uint256 _amount) public {
        IERC20(_token).approve(_spender, _amount);
    }

    function transfer(address _token, address _to, uint256 _amount) public {
        IERC20(_token).transfer(_to, _amount);
    }
}
