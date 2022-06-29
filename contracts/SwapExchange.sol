// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MediumAccessControl.sol";
import "./ISwapFactory.sol";
import "./ISwapExchange.sol";


contract SwapExchange is ISwapExchange, MediumAccessControl {
    using SafeMath for uint256;

    uint256 _totalLiquidity;                            // total supplied liquidity amount
    mapping (address => uint256) _liquidityBalances;    // supplied liquidity map [address to amount]

    IERC20 _token;              // address of the ERC20 token traded on this contract
    ISwapFactory _factory;      // interface for the factory that created this contract
    uint256 _feeInMille;        // fee in mille

    constructor (address token, uint256 feeInMille) {
        require (token != address(0), "invalid token");
        require (feeInMille < 1000, "invalid fee");
        _token = IERC20(token);
        _factory = ISwapFactory(msg.sender);
        _feeInMille = feeInMille; // uniswap은 3으로 셋팅해서 사용
    }

    function tokenAddress() external view returns (address) {
        return address(_token);
    }

    function factoryAddress() external view returns (address) {
        return address(_factory);
    }
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // X*Y=K 계산 기초 함수 [input amount => output amount]
    function calcOutputAmount(uint256 inputAmount, uint256 inputReserve, uint256 outputReserve) public view returns (uint256) {
        require (inputReserve > 0 && outputReserve > 0, "invalid input/output reserve value");
        uint256 inputAmountWithFee = inputAmount.mul(1000-_feeInMille);
        uint256 numerator = inputAmountWithFee.mul(outputReserve);
        uint256 denominator = inputReserve.mul(1000).add(inputAmountWithFee);
        return numerator.div(denominator);
    }
    // X*Y=K 계산 기초 함수 [output amount => input amount]
    function calcInputAmount(uint256 outputAmount, uint256 inputReserve, uint256 outputReserve) public view returns (uint256) {
        require (inputReserve > 0 && outputReserve > 0, "invalid input/output reserve value");
        uint256 numerator = inputReserve.mul(outputAmount).mul(1000);
        uint256 denominator = (outputReserve.sub(outputAmount)).mul(1000-_feeInMille);
        return (numerator.div(denominator)).add(1);
    }
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // [coin input amount => token output amount]
    function getTokenToCoinOutputAmount(uint256 coinInputAmount) external view returns (uint256) {
        require (coinInputAmount > 0, "invalid coin input amount");
        return calcOutputAmount(coinInputAmount, _token.balanceOf(address(this)), address(this).balance);
    }
    // [coin output amount => token input amount]
    function getCoinToTokenInputAmount(uint256 coinOutputAmount) external view returns (uint256) {
        require (coinOutputAmount > 0, "invalid coin output amount");
        return calcInputAmount(coinOutputAmount, address(this).balance, _token.balanceOf(address(this)));
    }
    // [token input amount => coin output amount]
    function getCoinToTokenOutputAmount(uint256 tokenInputAmount) external view returns (uint256) {
        require (tokenInputAmount > 0, "invalid token input amount");
        return calcOutputAmount(tokenInputAmount, address(this).balance, _token.balanceOf(address(this)));
    }
    // [token output amount => coin input amount]
    function getTokenToCoinInputAmount(uint256 tokenOutputAmount) external view returns (uint256) {
        require (tokenOutputAmount > 0, "invalid token output amount");
        return calcInputAmount(tokenOutputAmount, _token.balanceOf(address(this)), address(this).balance);
    }
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    receive() external payable {
        _coinToTokenInput(msg.value, 1, block.timestamp, msg.sender, msg.sender);
    }

    function swapCoinToToken(uint256 minTokenAmount, uint256 deadline) external payable returns (uint256) {
        return _coinToTokenInput(msg.value, minTokenAmount, deadline, msg.sender, msg.sender);
    }

    function swapCoinFromToken(uint256 tokenAmount, uint256 deadline) external payable returns(uint256) {
        return _coinToTokenOutput(tokenAmount, msg.value, deadline, msg.sender, msg.sender);
    }

    function swapTokenToCoin(uint256 tokenAmount, uint256 minCoinAmount, uint256 deadline) external returns (uint256) {
        return _tokenToCoinInput(tokenAmount, minCoinAmount, deadline, msg.sender, msg.sender);
    }

    function swapTokenFromCoin(uint256 coinAmount, uint256 maxTokenAmount, uint256 deadline) external returns (uint256) {
        return _tokenToCoinOutput(coinAmount, maxTokenAmount, deadline, msg.sender, msg.sender);
    }
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // order: coin sell [coin sell in => token buy out] - condition: msg.value(=coinInputAmout) transfer done
    function _coinToTokenInput(uint256 coinInputAmount, uint256 minTokenAmount, uint256 deadline, address buyer, address recipient) private returns (uint256) {
        require (deadline >= block.timestamp && coinInputAmount > 0, "invalid input param value");
        uint256 tokenOutputAmount = calcOutputAmount(coinInputAmount, address(this).balance.sub(coinInputAmount), _token.balanceOf(address(this)));
        require (tokenOutputAmount >= minTokenAmount, "must tokenOutAmount >= minTokenAmount");
        require (_token.transfer(recipient, tokenOutputAmount), "token transfer fail");
        emit TokenPurchase(buyer, coinInputAmount, tokenOutputAmount);
        return tokenOutputAmount;
    }
    // order:token buy [coin sell in => token buy out] - condition: msg.value(=paidCoinAmount) transfer done
    function _coinToTokenOutput(uint256 tokenOutputAmount, uint256 paidCoinAmount, uint256 deadline, address buyer, address recipient) private returns (uint256) {
        require (deadline >= block.timestamp && tokenOutputAmount > 0 && paidCoinAmount > 0, "invalid input param value");
        uint256 coinInputAmount = calcInputAmount(tokenOutputAmount, address(this).balance.sub(paidCoinAmount), _token.balanceOf(address(this)));
        require (paidCoinAmount >= coinInputAmount, "must coinInputAmount <= paidCoinAmount");
        uint256 coinRefundAmount = paidCoinAmount.sub(coinInputAmount);
        if (coinRefundAmount > 0) {
            payable(buyer).transfer(coinRefundAmount);
        }
        require (_token.transfer(recipient, tokenOutputAmount), "token transferFrom fail");
        emit TokenPurchase(buyer, coinInputAmount, tokenOutputAmount);
        return coinInputAmount;
    }
    // order:token sell [token sell in => coin buy out] - condition: approve done
    function _tokenToCoinInput(uint256 tokenInputAmount, uint256 minCoinAmount, uint256 deadline, address buyer, address recipient) private returns (uint256) {
        require (deadline >= block.timestamp && tokenInputAmount > 0);
        uint256 coinOutputAmount = calcOutputAmount(tokenInputAmount, _token.balanceOf(address(this)), address(this).balance);
        require (coinOutputAmount >= minCoinAmount, "must coinOutputAmount >= minCoinAmount");
        require (_token.transferFrom(buyer, address(this), tokenInputAmount), "token transferFrom fail");
        payable(recipient).transfer(coinOutputAmount);
        emit CoinPurchase(buyer, tokenInputAmount, coinOutputAmount);
        return coinOutputAmount;
    }
    // order:coin buy [token sell in => coin buy out] - condition: approve done
    function _tokenToCoinOutput(uint256 coinOutputAmount, uint256 maxTokenAmount, uint256 deadline, address buyer, address recipient) private returns (uint256) {
        require (deadline >= block.timestamp && coinOutputAmount > 0, "invalid input param value");
        uint256 tokenInputAmount = calcInputAmount(coinOutputAmount, _token.balanceOf(address(this)), address(this).balance);
        require (tokenInputAmount <= maxTokenAmount, "must tokenInputAmount <= maxTokenAmount");
        require (_token.transferFrom(buyer, address(this), tokenInputAmount), "token transferFrom fail");
        payable(recipient).transfer(coinOutputAmount);
        emit CoinPurchase(buyer, tokenInputAmount, coinOutputAmount);
        return tokenInputAmount;
    }
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // condition: coin value transfer done & token approve done
    function addLiquidity(uint256 maxTokenAmount, uint256 deadline) external payable returns (uint256) {
        
        require (deadline >= block.timestamp && maxTokenAmount > 0 && msg.value > 0, "invalid inputs");

        if (_totalLiquidity > 0) {

            uint256 coinReserve = address(this).balance.sub(msg.value);
            uint256 tokenReserve = _token.balanceOf(address(this));

            uint256 tokenAddAmount = (msg.value).mul(tokenReserve).div(coinReserve).add(1);
            uint256 liquidityMint = (msg.value).mul(_totalLiquidity).div(coinReserve);
            
            require (maxTokenAmount >= tokenAddAmount, "must maxTokenAmount >= tokenAddAmount");
            
            _liquidityBalances[msg.sender] = _liquidityBalances[msg.sender].add(liquidityMint);
            _totalLiquidity = _totalLiquidity.add(liquidityMint);
            
            require (_token.transferFrom(msg.sender, address(this), tokenAddAmount), "token transfer fail");
            
            emit AddLiquidity(msg.sender, msg.value, tokenAddAmount);
            
            return liquidityMint;

        } else {

            require (address(_factory) != address(0) && address(_token) != address(0) && msg.value >= 1000000000, "invalid inputs");
            require (_factory.getExchange(address(_token)) == address(this), "invalid exchange setting");
            
            uint256 tokenAddAmount = maxTokenAmount;
            uint256 initialLiquidity = address(this).balance;

            _totalLiquidity = initialLiquidity;
            _liquidityBalances[msg.sender] = initialLiquidity;
            
            require (_token.transferFrom(msg.sender, address(this), tokenAddAmount), "token transfer fail");
            
            emit AddLiquidity(msg.sender, msg.value, tokenAddAmount);
            
            return initialLiquidity;
        }
    }
    // condition: x
    function removeLiquidity(uint256 removeLiquidityAmount, uint256 minCoinRemoveAmount, uint256 minTokenRemoveAmount, uint256 deadline) external onlyAdmin returns (uint256, uint256) {
        
        require (removeLiquidityAmount > 0 && deadline >= block.timestamp && minCoinRemoveAmount > 0 && minTokenRemoveAmount > 0, "invalid inputs");
        require (_totalLiquidity > 0, "total liquidity is 0");
        
        uint256 coinReserve = address(this).balance;
        uint256 tokenReserve = _token.balanceOf(address(this));
        
        uint256 coinRemoveAmount = removeLiquidityAmount.mul(coinReserve).div(_totalLiquidity);
        uint256 tokenRemoveAmount = removeLiquidityAmount.mul(tokenReserve).div(_totalLiquidity);
        
        require (coinRemoveAmount >= minCoinRemoveAmount && tokenRemoveAmount >= minTokenRemoveAmount);

        _liquidityBalances[msg.sender] = _liquidityBalances[msg.sender].sub(removeLiquidityAmount);
        _totalLiquidity = _totalLiquidity.sub(removeLiquidityAmount);
        
        payable(msg.sender).transfer(coinRemoveAmount);
        require (_token.transfer(msg.sender, tokenRemoveAmount), "token transfer fail");
        
        emit RemoveLiquidity(msg.sender, coinRemoveAmount, tokenRemoveAmount);
        
        return (coinRemoveAmount, tokenRemoveAmount);
    }
}
