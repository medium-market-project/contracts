// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

interface ISwapExchange {

    event TokenPurchase(address indexed buyer, uint256 indexed coinSold, uint256 indexed tokenBought);
    event CoinPurchase(address indexed buyer, uint256 indexed tokenSold, uint256 indexed coinBought);
    event AddLiquidity(address indexed provider, uint256 indexed coinAmount, uint256 indexed tokenAmount);
    event RemoveLiquidity(address indexed provider, uint256 indexed coinAmount, uint256 indexed tokenAmount);

    receive() external payable;
    function swapCoinToToken(uint256 minTokenAmount, uint256 deadline) external payable returns (uint256);
    function swapCoinFromToken(uint256 tokenAmount, uint256 deadline) external payable returns(uint256);
    function swapTokenToCoin(uint256 tokenAmount, uint256 minCoinAmount, uint256 deadline) external returns (uint256);
    function swapTokenFromCoin(uint256 coinAmount, uint256 maxTokenAmount, uint256 deadline) external returns (uint256);
    
    function getTokenToCoinOutputAmount(uint256 coinInputAmount) external view returns (uint256);
    function getCoinToTokenInputAmount(uint256 coinOutputAmount) external view returns (uint256);
    function getCoinToTokenOutputAmount(uint256 tokenInputAmount) external view returns (uint256);
    function getTokenToCoinInputAmount(uint256 tokenOutputAmount) external view returns (uint256);

    function calcOutputAmount(uint256 inputAmount, uint256 inputReserve, uint256 outputReserve, uint256 feeInMille) external view returns (uint256);
    function calcInputAmount(uint256 outputAmount, uint256 inputReserve, uint256 outputReserve, uint256 feeInMille) external view returns (uint256);

    function tokenAddress() external view returns (address);
    function factoryAddress() external view returns (address);

    function addLiquidity(uint256 maxTokenAmount, uint256 deadline) external payable returns (uint256);
    function removeLiquidity(uint256 removeLiquidityAmount, uint256 minCoinRemoveAmount, uint256 minTokenRemoveAmount, uint256 deadline) external returns (uint256, uint256);
}
