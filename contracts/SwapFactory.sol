// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/utils/Counters.sol";
import "./MediumAccessControl.sol";
import "./SwapExchange.sol";


contract SwapFactory is ISwapFactory, MediumAccessControl {
    using Counters for Counters.Counter;

    Counters.Counter _tokenIdxCounter;

    mapping (address => address) _tokenToExchange;
    mapping (address => address) _exchangeToToken;
    mapping (uint256 => address) _idxToToken;

    function createExchange(address token) external onlyAdmin returns (address) {
        require(token != address(0), "invalid token address");
        require(_tokenToExchange[token] == address(0), "exist token");

        SwapExchange exchange = new SwapExchange(token, 3);
        
        _tokenToExchange[token] = address(exchange);
        _exchangeToToken[address(exchange)] = token;
        _idxToToken[_tokenIdxCounter.current()] = token;
        _tokenIdxCounter.increment();
        
        emit CreateExchange(token, address(exchange));
        
        return address(exchange);
    }

    function getExchange(address token) public view returns (address) {
        return _tokenToExchange[token];
    }

    function getToken(address exchange) public view returns (address) {
        return _exchangeToToken[exchange];
    }

    function getTokenWithIdx(uint256 tokenIdx) public view returns (address) {
        return _idxToToken[tokenIdx];
    }
}
