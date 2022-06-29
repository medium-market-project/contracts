// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MediumAccessControl.sol";
import "./MediumPausable.sol";

contract MediumSwapAgentK is MediumAccessControl, MediumPausable {

    IERC20 reserveToken;

    event SwapInK(uint indexed swapKey, address indexed from, uint amount);
    event SwapOutK(uint indexed swapKey, address indexed to, uint amount);

    constructor(address tokenAddress) {
        setReserveToken(tokenAddress);
    }

    function setReserveToken(address tokenAddress) public onlyAdmin {
        require (tokenAddress != address(0), "invalid token address");
        reserveToken = IERC20(tokenAddress);
    }

    function withdrawReserve(address to, uint amount) external onlyAdmin {
        require (amount <= reserveToken.balanceOf(address(this)), "insufficient reserve");
        require (reserveToken.transfer(to, amount), "token transfer fail");
    }

    function swapIn(uint swapKey, uint amount) external whenNotPaused {
        require (amount <= reserveToken.balanceOf(msg.sender), "insufficient balance");
        require (reserveToken.transferFrom(msg.sender, address(this), amount), "token transfer fail");
        emit SwapInK(swapKey, msg.sender, amount);
    }

    function swapOut(uint swapKey, address to, uint amount) external onlyAdmin {
        require (to != address(0), "invalid address");
        require (amount <= reserveToken.balanceOf(address(this)), "insufficient reserve");
        require (reserveToken.transfer(to, amount), "token transfer fail");
        emit SwapOut(swapKey, to, amount);
    }
}
