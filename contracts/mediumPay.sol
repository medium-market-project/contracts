// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
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

contract MediumMarketAgent is MediumAccessControl, MediumPausable {

    using SafeMath for uint;
    using Counters for Counters.Counter;

    enum PayType { BUY_NOW, EVENT_APPLY }
    enum PayState { PAID, REFUNDED, CANCELLED, COMPLETED }

    Counters.Counter private _payIdxCounter;

    struct PayReceipt {
        PayType payType;
        PayState payState;
        uint payIdx;
        uint marketKey;
        uint unitPrice;
        uint amount;
        address nftContract;
        address seller;
        address buyer;
        uint timestamp;
        uint refundAmount;
    }

    mapping(address => mapping(uint => PayReceipt)) payBook;

    event Pay(uint payIdx, PayType payType, uint indexed marketKey, address indexed buyer, uint unitPrice, uint amount);
    event Refund(uint payIdx, PayType payType, uint indexed marketKey, address indexed buyer, uint unitPrice, uint amount, uint refundAmount);
    event Cancel(uint payIdx, PayType payType, uint indexed marketKey, address indexed buyer, uint unitPrice, uint amount, uint refundAmount);
    event Payout(uint payIdx, PayType payType, uint indexed marketKey, address indexed buyer, uint unitPrice, uint amount);

    function payForBuyNow(uint orderNum, address seller, address nftcontract, uint unitPrice, uint amount) external payable whenNotPaused {
        
        require(unitPrice.mul(amount) == msg.value, "transfered value must match the price");

        PayReceipt memory receipt;
        receipt.payType = PayType.BUY_NOW;
        receipt.payState = PayState.PAID;
        receipt.payIdx = _payIdxCounter.current();
        receipt.marketKey = orderNum;
        receipt.unitPrice = unitPrice;
        receipt.amount = amount;
        receipt.refundAmount = 0;
        receipt.nftContract = nftcontract;
        receipt.seller = seller;
        receipt.buyer = msg.sender;
        receipt.timestamp = block.timestamp;

        payBook[receipt.buyer][receipt.marketKey] = receipt;
        
        _payIdxCounter.increment();

        emit Pay(receipt.payIdx, receipt.payType, receipt.marketKey, receipt.buyer, receipt.unitPrice, receipt.amount);
    }

    function payForEventApply(uint eventItemNum, address seller, address nftcontract, uint unitPrice, uint amount) external payable whenNotPaused {
        require(unitPrice.mul(amount) == msg.value, "transfered value must match the price");

        PayReceipt memory receipt = payBook[msg.sender][eventItemNum];
        if (receipt.marketKey > 0) {
            require(receipt.payState == PayState.PAID, "PayState is not PAID.");
            require(receipt.marketKey == eventItemNum, "MarketKey is not match.");
            require(receipt.unitPrice == unitPrice, "UnitPrice is not match.");
            
            receipt.amount += amount;

            payBook[receipt.buyer][receipt.marketKey] = receipt;
        } else {
            receipt.payType = PayType.EVENT_APPLY;
            receipt.payState = PayState.PAID;
            receipt.payIdx = _payIdxCounter.current();
            receipt.marketKey = eventItemNum;
            receipt.unitPrice = unitPrice;
            receipt.amount = amount;
            receipt.refundAmount = 0;
            receipt.nftContract = nftcontract;
            receipt.seller = seller;
            receipt.buyer = msg.sender;
            receipt.timestamp = block.timestamp;

            payBook[receipt.buyer][receipt.marketKey] = receipt;

            _payIdxCounter.increment();
        }

        emit Pay(receipt.payIdx, receipt.payType, receipt.marketKey, receipt.buyer, receipt.unitPrice, receipt.amount);
    }
    
    function refund(address buyer, uint marketKey, uint amount) external onlyAdmin {
        _refund(buyer, marketKey, amount);
    }

    function payout(address buyer, uint marketKey, address[] memory payoutAddresses, uint[] memory payoutRatios) external onlyAdmin {
        _payout(buyer, marketKey, payoutAddresses, payoutRatios);
    }

    function refundAndPayout(address buyer, uint marketKey, uint refundAmount, address[] memory payoutAddresses, uint[] memory payoutRatios) external onlyAdmin {
        _refund(buyer, marketKey, refundAmount);
        _payout(buyer, marketKey, payoutAddresses, payoutRatios);
    }

    function _refund(address buyer, uint marketKey, uint amount) internal {
        PayReceipt memory receipt = payBook[buyer][marketKey];
        
        require(receipt.marketKey > 0, "no receipt found");
        require(receipt.payState == PayState.PAID, "refund is not allowed");
        require(amount > 0 && receipt.amount <= amount, "must be 0 < refund amount <= paid amount ");
        require(address(this).balance >= receipt.unitPrice.mul(amount), "Depository balance is not enough to refund");
        
        payable(receipt.buyer).transfer(receipt.unitPrice.mul(amount));
        
        receipt.refundAmount.add(amount);
        receipt.amount.sub(amount);

        if (receipt.amount == 0) {
            receipt.payState = PayState.CANCELLED;
            payBook[buyer][marketKey] = receipt;
            emit Cancel(receipt.payIdx, receipt.payType, receipt.marketKey, receipt.buyer, receipt.unitPrice, receipt.amount, receipt.refundAmount);
        } else {
            receipt.payState = PayState.REFUNDED;
            payBook[buyer][marketKey] = receipt;
            emit Refund(receipt.payIdx, receipt.payType, receipt.marketKey, receipt.buyer, receipt.unitPrice, receipt.amount, receipt.refundAmount);
        }
    }

    function _payout(address buyer, uint marketKey, address[] memory payoutAddresses, uint[] memory payoutRatios) internal {
        PayReceipt memory receipt = payBook[buyer][marketKey];

        require(receipt.marketKey > 0, "no receipt found");
        require(receipt.payState == PayState.PAID || receipt.payState == PayState.REFUNDED, "payout is not allowed");
        require(receipt.amount > 0, "must be 0 < amount");
        require(address(this).balance >= receipt.unitPrice.mul(receipt.amount), "Depository balance is not enough to payout");
        require(payoutAddresses.length > 0 && payoutAddresses.length == payoutRatios.length, "payout pair must match");

        uint totalPayment = receipt.unitPrice.mul(receipt.amount);
        uint payoutRatioSum = 0;
        for (uint i = 0; i < payoutAddresses.length; i++) {
            payoutRatioSum += payoutRatios[i];
        }
        for (uint i = 0; i < payoutAddresses.length; i++) {
            if (payoutRatios[i] > 0) {
                payable(payoutAddresses[i]).transfer(totalPayment.mul(payoutRatios[i].div(payoutRatioSum)));
            }
        }

        receipt.payState = PayState.COMPLETED;
        payBook[buyer][marketKey] = receipt;
        emit Payout(receipt.payIdx, receipt.payType, receipt.marketKey, receipt.buyer, receipt.unitPrice, receipt.amount);
    }

    function getReceipt(address buyer, uint marketKey) external view returns (PayType, PayState, uint, uint, uint, uint, address, address, address, uint, uint) {
        PayReceipt memory receipt = payBook[buyer][marketKey];
        
        require(receipt.marketKey > 0, "no receipt found");
        
        return (receipt.payType, receipt.payState, receipt.payIdx, receipt.marketKey, receipt.unitPrice, receipt.amount, receipt.nftContract, receipt.seller, receipt.buyer, receipt.timestamp, receipt.refundAmount);
    }

}
