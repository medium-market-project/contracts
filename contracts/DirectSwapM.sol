// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "./MediumAccessControl.sol";
import "./MediumPausable.sol";

contract MediumSwapAgentM is MediumAccessControl, MediumPausable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    event WithdrawReserveM(address indexed admin, address indexed to, uint amount);
    event SwapInM(uint indexed swapKey, address indexed from, uint amount);
    event SwapOutM(uint indexed swapKey, address indexed to, uint amount);
    event SwapRefundM(uint indexed swapKey, address indexed to, uint amount);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function withdrawReserve(address to, uint amount) external onlyAdmin {
        require (amount <= address(this).balance, "insufficient reserve");
        payable(to).transfer(amount);
        emit WithdrawReserveM(msg.sender, to, amount);
    }

    function swapIn(uint swapKey) payable external whenNotPaused {
        emit SwapInM(swapKey, msg.sender, msg.value);
    }

    function swapOut(uint swapKey, address to, uint amount) external onlyAdmin {
        require (to != address(0), "invalid address");
        require (amount <= address(this).balance, "insufficient reserve");
        payable(to).transfer(amount);
        emit SwapOutM(swapKey, to, amount);
    }
    
    function swapRefund(uint swapKey, address to, uint amount) external onlyAdmin {
        require (to != address(0), "invalid address");
        require (amount <= address(this).balance, "insufficient reserve");
        payable(to).transfer(amount);
        emit SwapRefundM(swapKey, to, amount);
    }
}
