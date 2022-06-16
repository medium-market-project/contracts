// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract MediumAccessControl is AccessControl {
    
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");
    
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    modifier onlyAdmin() {
        _checkRole(ADMIN_ROLE);
        _;
    }
}

contract MediumPausable is Pausable, Ownable {

    function setPause() external onlyOwner {
        _pause();
    }

    function setUnpause() external onlyOwner {
        _unpause();
    }
}

contract MediumSwapAgentM is MediumAccessControl, MediumPausable {

    mapping(address => uint) swapDepository;

    event SwapIn(address indexed from, uint amount);
    event SwapOut(address indexed to, uint amount);

    function withdrawReserve(address to, uint amount) external onlyAdmin {
        require (amount <= address(this).balance, "insufficient reserve");
        payable(to).transfer(amount);
    }

    function swapIn() payable external whenNotPaused {
        swapDepository[msg.sender] += msg.value;
        emit SwapIn(msg.sender, msg.value);
    }

    function swapOut(address to, uint amount) external onlyAdmin {
        require (to != address(0), "invalid address");
        require (amount <= address(this).balance, "insufficient reserve");
        require (amount <= swapDepository[to], "insufficient deposit");
        payable(to).transfer(amount);
        swapDepository[to] -= amount;
        emit SwapOut(to, amount);
    }
}
