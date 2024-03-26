// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.20 <0.9.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ERC721ReceiverMock} from "@openzeppelin/contracts/mocks/token/ERC721ReceiverMock.sol";

contract TestOwner is ERC721ReceiverMock {
    constructor() ERC721ReceiverMock(IERC721Receiver.onERC721Received.selector, RevertType.None) {}

    function approve(address _token, address _spender, uint256 _amount) public {
        IERC20(_token).approve(_spender, _amount);
    }

    function transfer(address _token, address _to, uint256 _amount) public {
        IERC20(_token).transfer(_to, _amount);
    }
}
