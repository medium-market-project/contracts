// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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

contract MediumSwapAgentK is MediumAccessControl, MediumPausable {

    mapping(address => uint) swapDepository;

    IERC20 reserveToken;

    event SwapIn(address indexed from, uint amount);
    event SwapOut(address indexed to, uint amount);

    constructor(address tokenAddress) {
        setReserveToken(tokenAddress);
    }

    function setReserveToken(address tokenAddress) public onlyAdmin {
        require (tokenAddress != address(0), "invalid token address");
        reserveToken = IERC20(tokenAddress);
    }

    function withdrawReserve(address to, uint amount) external onlyAdmin {
        require (amount <= reserveToken.balanceOf(address(this)), "insufficient reserve");
        reserveToken.transfer(to, amount);
    }

    function swapIn(uint amount) external whenNotPaused {
        require (amount <= reserveToken.balanceOf(msg.sender), "insufficient balance");
        reserveToken.transfer(address(this), amount);
        swapDepository[msg.sender] += amount;
        emit SwapIn(msg.sender, amount);
    }

    function swapOut(address to, uint amount) external onlyAdmin {
        require (to != address(0), "invalid address");
        require (amount <= reserveToken.balanceOf(address(this)), "insufficient reserve");
        require (amount <= swapDepository[to], "insufficient deposit");
        reserveToken.transfer(to, amount);
        swapDepository[to] -= amount;
        emit SwapOut(to, amount);
    }
}
