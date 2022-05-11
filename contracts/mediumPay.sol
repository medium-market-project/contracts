// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeMath.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Counters.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/AccessControl.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/Pausable.sol";

contract MediumAccessControl is AccessControl {
    
    bytes32 public constant SUPERVISOR_ROLE = keccak256("SUPERVISOR");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");
    
    constructor() {
        _setupRole(SUPERVISOR_ROLE, _msgSender());
        _setRoleAdmin(SUPERVISOR_ROLE, SUPERVISOR_ROLE);

        _setupRole(ADMIN_ROLE, _msgSender());
        _setRoleAdmin(ADMIN_ROLE, SUPERVISOR_ROLE);
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
        uint itemId;
        uint unitPrice;
        uint amount;
        uint tokenId;
        address nftContract;
        address seller;
        address buyer;
        address [] payoutAddresses;
        uint [] payoutRatios;
        uint timestamp;
        uint refundAmount;
    }

    mapping(uint => PayReceipt) payBook;

    event Pay(uint indexed payIdx, PayType payType, uint indexed itemId, address indexed buyer, uint unitPrice, uint amount);
    event Refund(uint indexed payIdx, PayType payType, uint indexed itemId, address indexed buyer, uint unitPrice, uint amount, uint refundAmount);
    event Cancel(uint indexed payIdx, PayType payType, uint indexed itemId, address indexed buyer, uint unitPrice, uint amount, uint refundAmount);
    event Payout(uint indexed payIdx, PayType payType, uint indexed itemId, address indexed buyer, uint unitPrice, uint amount);

    function payForBuyNow(uint itemId, address seller, address nftcontract, uint tokenId, uint unitPrice, uint amount, address [] memory payoutAddresses, uint[] memory payoutRatios) external payable whenNotPaused returns (uint) {
        PayReceipt memory receipt;
        receipt.payType = PayType.BUY_NOW;
        receipt.tokenId = tokenId;
        
        return pay(receipt, itemId, seller, nftcontract, unitPrice, amount, payoutAddresses, payoutRatios);
    }

    function payForEventApply(uint eventId, address seller, address nftcontract, uint amount, uint unitPrice, address[] memory payoutAddresses, uint[] memory payoutRatios) external payable whenNotPaused returns (uint) {
        PayReceipt memory receipt;
        receipt.payType = PayType.EVENT_APPLY;
        
        return pay(receipt, eventId, seller, nftcontract, unitPrice, amount, payoutAddresses, payoutRatios);
    }

    function pay(PayReceipt memory receipt, uint itemId, address seller, address nftcontract, uint unitPrice, uint amount, address[] memory payoutAddresses, uint[] memory payoutRatios) internal returns (uint) {
        require(unitPrice.mul(amount) == msg.value, "transfered value must match the price");
        require(payoutAddresses.length > 0 && payoutAddresses.length == payoutRatios.length, "payout pair must match");

        receipt.payState = PayState.PAID;
        receipt.payIdx = _payIdxCounter.current();
        receipt.itemId = itemId;
        receipt.unitPrice = unitPrice;
        receipt.amount = amount;
        receipt.refundAmount = 0;
        receipt.nftContract = nftcontract;
        receipt.seller = seller;
        receipt.buyer = msg.sender;
        receipt.payoutAddresses = payoutAddresses;
        receipt.payoutRatios = payoutRatios;
        receipt.timestamp = block.timestamp;

        payBook[_payIdxCounter.current()] = receipt;
        _payIdxCounter.increment();

        emit Pay(receipt.payIdx, receipt.payType, receipt.itemId, receipt.buyer, receipt.unitPrice, receipt.amount);

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
            emit Cancel(receipt.payIdx, receipt.payType, receipt.itemId, receipt.buyer, receipt.unitPrice, receipt.amount, receipt.refundAmount);
        } else {
            receipt.payState = PayState.REFUNDED;
            emit Refund(receipt.payIdx, receipt.payType, receipt.itemId, receipt.buyer, receipt.unitPrice, receipt.amount, receipt.refundAmount);
        }
    }

    function payout(uint payIdx) external onlyAdmin {
        PayReceipt memory receipt = payBook[payIdx];

        require(receipt.payState == PayState.PAID || receipt.payState == PayState.REFUNDED, "payout is not allowed");
        require(receipt.amount > 0, "must be 0 < amount");
        require(address(this).balance >= receipt.unitPrice.mul(receipt.amount), "Depository balance is not enough to payout");

        uint totalPayment = receipt.unitPrice.mul(receipt.amount);
        uint payoutRatioSum = 0;
        for (uint i = 0; i < receipt.payoutAddresses.length; i++) {
            payoutRatioSum += receipt.payoutRatios[i];
        }
        for (uint i = 0; i < receipt.payoutAddresses.length; i++) {
            if (receipt.payoutRatios[i] > 0) {
                payable(receipt.payoutAddresses[i]).transfer(totalPayment.mul(receipt.payoutRatios[i].div(payoutRatioSum)));
            }
        }

        receipt.payState = PayState.COMPLETED;

        emit Payout(receipt.payIdx, receipt.payType, receipt.itemId, receipt.buyer, receipt.unitPrice, receipt.amount);
    }
}
