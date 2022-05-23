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
        uint orderIdx;
        uint unitPrice;
        uint amount;
        address nftContract;
        address seller;
        address buyer;
        uint timestamp;
        uint refundAmount;
    }

    mapping(uint => PayReceipt) payBook;

    event Pay(uint indexed payIdx, PayType payType, uint indexed orderIdx, address indexed buyer, uint unitPrice, uint amount);
    event Refund(uint indexed payIdx, PayType payType, uint indexed orderIdx, address indexed buyer, uint unitPrice, uint amount, uint refundAmount);
    event Cancel(uint indexed payIdx, PayType payType, uint indexed orderIdx, address indexed buyer, uint unitPrice, uint amount, uint refundAmount);
    event Payout(uint indexed payIdx, PayType payType, uint indexed orderIdx, address indexed buyer, uint unitPrice, uint amount);

    function payForBuyNow(uint orderIdx, address seller, address nftcontract, uint unitPrice, uint amount) external payable whenNotPaused returns (uint) {
        PayReceipt memory receipt;
        receipt.payType = PayType.BUY_NOW;
        
        return pay(receipt, orderIdx, seller, nftcontract, unitPrice, amount);
    }

    function payForEventApply(uint orderIdx, address seller, address nftcontract, uint unitPrice, uint amount) external payable whenNotPaused returns (uint) {
        PayReceipt memory receipt;
        receipt.payType = PayType.EVENT_APPLY;
        
        return pay(receipt, orderIdx, seller, nftcontract, unitPrice, amount);
    }

    function pay(PayReceipt memory receipt, uint orderIdx, address seller, address nftcontract, uint unitPrice, uint amount) internal returns (uint) {
        require(unitPrice.mul(amount) == msg.value, "transfered value must match the price");

        receipt.payState = PayState.PAID;
        receipt.payIdx = _payIdxCounter.current();
        receipt.orderIdx = orderIdx;
        receipt.unitPrice = unitPrice;
        receipt.amount = amount;
        receipt.refundAmount = 0;
        receipt.nftContract = nftcontract;
        receipt.seller = seller;
        receipt.buyer = msg.sender;
        receipt.timestamp = block.timestamp;

        payBook[_payIdxCounter.current()] = receipt;
        _payIdxCounter.increment();

        emit Pay(receipt.payIdx, receipt.payType, receipt.orderIdx, receipt.buyer, receipt.unitPrice, receipt.amount);

        return receipt.payIdx;
    }

    function refund(uint payIdx, uint amount) external onlyAdmin {
        PayReceipt memory receipt = payBook[payIdx];
        
        require(receipt.payState == PayState.PAID, "refund is not allowed");
        require(amount > 0 && receipt.amount <= amount, "must be 0 < refund amount <= paid amount ");
        require(address(this).balance >= receipt.unitPrice.mul(amount), "Depository balance is not enough to refund");
        
        payable(receipt.buyer).transfer(receipt.unitPrice.mul(amount));
        
        receipt.refundAmount.add(amount);
        receipt.amount.sub(amount);

        if (receipt.amount == 0) {
            receipt.payState = PayState.CANCELLED;
            emit Cancel(receipt.payIdx, receipt.payType, receipt.orderIdx, receipt.buyer, receipt.unitPrice, receipt.amount, receipt.refundAmount);
        } else {
            receipt.payState = PayState.REFUNDED;
            emit Refund(receipt.payIdx, receipt.payType, receipt.orderIdx, receipt.buyer, receipt.unitPrice, receipt.amount, receipt.refundAmount);
        }
    }

    function payout(uint payIdx, address[] memory payoutAddresses, uint[] memory payoutRatios) external onlyAdmin {
        PayReceipt memory receipt = payBook[payIdx];

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

        emit Payout(receipt.payIdx, receipt.payType, receipt.orderIdx, receipt.buyer, receipt.unitPrice, receipt.amount);
    }
    
    function getReceipt(uint payIdx) external view returns (PayType, PayState, uint, uint, uint, uint, address, address, address, uint, uint) {
        PayReceipt memory receipt = payBook[payIdx];
        return (receipt.payType, receipt.payState, receipt.payIdx, receipt.orderIdx, receipt.unitPrice, receipt.amount, receipt.nftContract, receipt.seller, receipt.buyer, receipt.timestamp, receipt.refundAmount);
    }

}
