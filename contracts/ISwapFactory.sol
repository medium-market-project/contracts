// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

interface ISwapFactory {
    event CreateExchange(address indexed token, address indexed exchange);

    function createExchange(address token, string calldata name, string calldata symbol) external returns (address);
    function getExchange(address token) external view returns (address);
    function getToken(address exchange) external view returns (address);
    function getTokenWithIdx(uint256 tokenIdx) external view returns (address);
}
