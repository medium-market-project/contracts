// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "./MediumAccessControl.sol";
import "./MediumPausable.sol";

contract MediumSwapAgentM is MediumAccessControl, MediumPausable {

    event SwapIn(address indexed from, uint amount);
    event SwapOut(address indexed to, uint amount);

    function withdrawReserve(address to, uint amount) external onlyAdmin {
        require (amount <= address(this).balance, "insufficient reserve");
        payable(to).transfer(amount);
    }

    function swapIn() payable external whenNotPaused {
        emit SwapIn(msg.sender, msg.value);
    }

    function swapOut(address to, uint amount) external onlyAdmin {
        require (to != address(0), "invalid address");
        require (amount <= address(this).balance, "insufficient reserve");
        payable(to).transfer(amount);
        emit SwapOut(to, amount);
    }
}
