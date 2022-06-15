// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./MediumAccessControl.sol";
import "./MediumPausable.sol";

contract MediumMarketAgent is MediumAccessControl, MediumPausable {

    using SafeMath for uint;
    using Counters for Counters.Counter;

    enum PayType { BUY_NOW, EVENT_APPLY }

    Counters.Counter private _payIdxCounter;

    struct PayReceipt {
        PayType payType;
        uint payIdx;
        uint marketKey;
        uint unitPrice;
        uint buyAmount;
        uint refundAmount;
        uint payoutAmount;
        address nftContract;
        address seller;
        address buyer;
        uint timestamp;
    }

    mapping(address => mapping(uint => PayReceipt)) payBook;

    event Pay(uint indexed payIdx, uint indexed marketKey, address indexed buyer, PayType payType, uint unitPrice, uint buyAmount);
    event Refund(uint indexed payIdx, uint indexed marketKey, address indexed buyer, PayType payType, uint unitPrice, uint refundAmount);
    event Payout(uint indexed payIdx, uint indexed marketKey, address indexed buyer, PayType payType, uint unitPrice, uint payoutAmount, address[] payoutAddresses, uint[] payout);
    event RefundAndPayout(uint indexed payIdx, uint indexed marketKey, address indexed buyer, PayType payType, uint unitPrice, uint refundAmount, uint payoutAmount, address[] payoutAddresses, uint[] payout);


    function payForBuyNow(uint orderNum, address seller, address nftcontract, uint unitPrice, uint buyAmount) external payable whenNotPaused {
        
        require(unitPrice.mul(buyAmount) == msg.value, "transfered value must match the price");

        PayReceipt memory receipt;
        receipt.payType = PayType.BUY_NOW;
        receipt.payIdx = _payIdxCounter.current();
        receipt.marketKey = orderNum;
        receipt.unitPrice = unitPrice;
        receipt.buyAmount = buyAmount;
        receipt.refundAmount = 0;
        receipt.payoutAmount = 0;
        receipt.nftContract = nftcontract;
        receipt.seller = seller;
        receipt.buyer = msg.sender;
        receipt.timestamp = block.timestamp;

        payBook[receipt.buyer][receipt.marketKey] = receipt;
        
        _payIdxCounter.increment();

        emit Pay(receipt.payIdx, receipt.marketKey, receipt.buyer, receipt.payType, receipt.unitPrice, receipt.buyAmount);
    }

    function payForEventApply(uint eventItemNum, address seller, address nftcontract, uint unitPrice, uint buyAmount) external payable whenNotPaused {
        require(unitPrice.mul(buyAmount) == msg.value, "transfered value must match the price");

        PayReceipt memory receipt = payBook[msg.sender][eventItemNum];
        if (receipt.marketKey > 0) {
            require(receipt.marketKey == eventItemNum, "MarketKey is not match.");
            require(receipt.unitPrice == unitPrice, "UnitPrice is not match.");
            
            receipt.buyAmount += buyAmount;

            payBook[receipt.buyer][receipt.marketKey] = receipt;
        } else {
            receipt.payType = PayType.EVENT_APPLY;
            receipt.payIdx = _payIdxCounter.current();
            receipt.marketKey = eventItemNum;
            receipt.unitPrice = unitPrice;
            receipt.buyAmount = buyAmount;
            receipt.refundAmount = 0;
            receipt.payoutAmount = 0;
            receipt.nftContract = nftcontract;
            receipt.seller = seller;
            receipt.buyer = msg.sender;
            receipt.timestamp = block.timestamp;

            payBook[receipt.buyer][receipt.marketKey] = receipt;

            _payIdxCounter.increment();
        }

        emit Pay(receipt.payIdx, receipt.marketKey, receipt.buyer, receipt.payType, receipt.unitPrice, buyAmount);
    }
    
    function refund(address buyer, uint marketKey, uint refundAmount) external onlyAdmin {
        _refund(buyer, marketKey, refundAmount);
    }

    function payout(address buyer, uint marketKey, uint payoutAmount, address[] memory payoutAddresses, uint[] memory payoutRatios) external onlyAdmin {
        _payout(buyer, marketKey, payoutAmount, payoutAddresses, payoutRatios);
    }

    function refundAndPayout(address buyer, uint marketKey, uint refundAmount, uint payoutAmount, address[] memory payoutAddresses, uint[] memory payoutRatios) external onlyAdmin {
        _refund(buyer, marketKey, refundAmount);
        uint[] memory payoutValues = _payout(buyer, marketKey, payoutAmount, payoutAddresses, payoutRatios);

        PayReceipt memory receipt = payBook[buyer][marketKey];
        require(receipt.marketKey > 0, "no receipt found");

        emit RefundAndPayout(receipt.payIdx, receipt.marketKey, receipt.buyer, receipt.payType, receipt.unitPrice, refundAmount, payoutAmount, payoutAddresses, payoutValues);
    }

    function _refund(address buyer, uint marketKey, uint refundAmount) internal {
        PayReceipt memory receipt = payBook[buyer][marketKey];
        
        require(receipt.marketKey > 0, "no receipt found");
        require(receipt.buyAmount >= receipt.refundAmount + receipt.payoutAmount + refundAmount, "refundAmount exceed");
        require(address(this).balance >= receipt.unitPrice.mul(refundAmount), "Depository balance is not enough to refund");
        
        if (refundAmount > 0) {
            payable(receipt.buyer).transfer(receipt.unitPrice.mul(refundAmount));
            receipt.refundAmount += refundAmount;
            payBook[buyer][marketKey] = receipt;
        }

        emit Refund(receipt.payIdx, receipt.marketKey, receipt.buyer, receipt.payType, receipt.unitPrice, refundAmount);
    }

    function _payout(address buyer, uint marketKey, uint payoutAmount, address[] memory payoutAddresses, uint[] memory payoutRatios) internal returns (uint[] memory payouts) {
        PayReceipt memory receipt = payBook[buyer][marketKey];

        require(receipt.marketKey > 0, "no receipt found");
        require(receipt.buyAmount >= receipt.refundAmount + receipt.payoutAmount + payoutAmount, "payoutAmount exceed");
        require(address(this).balance >= receipt.unitPrice.mul(payoutAmount), "Depository balance is not enough to payout");
        require(payoutAddresses.length > 0 && payoutAddresses.length == payoutRatios.length, "payout pair must match");

        if (payoutAmount > 0) {
            uint totalPayment = receipt.unitPrice.mul(payoutAmount);
            uint payoutRatioSum = 0;
            uint[] memory payoutValues = new uint[] (payoutAddresses.length);
            for (uint i = 0; i < payoutAddresses.length; i++) {
                payoutRatioSum += payoutRatios[i];
            }
            for (uint i = 0; i < payoutAddresses.length; i++) {
                if (payoutRatios[i] > 0) {
                    uint payoutVal = totalPayment.mul(payoutRatios[i]).div(payoutRatioSum);
                    payoutValues[i] = payoutVal;
                    payable(payoutAddresses[i]).transfer(payoutVal);
                } else {
                    payoutValues[i] = 0;
                }
            }

            receipt.payoutAmount += payoutAmount;
            payBook[buyer][marketKey] = receipt;

            emit Payout(receipt.payIdx, receipt.marketKey, receipt.buyer, receipt.payType, receipt.unitPrice, payoutAmount, payoutAddresses, payoutValues);

            return payoutValues;
        } else {
            uint[] memory payoutValues = new uint[](0);
            
            emit Payout(receipt.payIdx, receipt.marketKey, receipt.buyer, receipt.payType, receipt.unitPrice, payoutAmount, payoutAddresses, payoutValues);
            
            return payoutValues;
        }
    }

    function getReceipt(address buyer, uint marketKey) external view returns (PayType, uint, uint, uint, uint, address, address, address, uint, uint, uint) {
        PayReceipt memory receipt = payBook[buyer][marketKey];
        require(receipt.marketKey > 0, "no receipt found");
        return (receipt.payType, receipt.payIdx, receipt.marketKey, receipt.unitPrice, receipt.buyAmount, receipt.nftContract, receipt.seller, receipt.buyer, receipt.timestamp, receipt.refundAmount, receipt.payoutAmount);
    }

}
