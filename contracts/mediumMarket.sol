// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/math/SafeMath.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/IERC721.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/PullPayment.sol";

interface IERC721Creator is IERC721 {
    function tokenCreator(uint256 _tokenId) external view returns (address payable);
}

interface ITxProxy {
    function sendMoney(address payable _to) external payable;
}

contract TxProxy is ITxProxy {
    function sendMoney(address payable _to) external payable {
        _to.transfer(msg.value);
    }
}

contract MaybeSendMoney {
    TxProxy proxy;

    constructor() {
        proxy = new TxProxy();
    }

    function maybeSendMoney(address payable _to, uint256 _value) internal returns (bool) {
        (bool success,) = address(proxy).call{value:_value}( abi.encodeWithSignature("sendMoney(address)", _to));
        return success;
    }
}

contract SendMoneyOrEscrow is Ownable, MaybeSendMoney, PullPayment {
    function sendMoneyOrEscrow(address payable _to, uint256 _value) internal {
        bool successfulTransfer = maybeSendMoney(_to, _value);
        if (!successfulTransfer) {
            _asyncTransfer(_to, _value);
        }
    }
}

contract Marketplace is Ownable, SendMoneyOrEscrow {
    using SafeMath for uint256;

    struct ActiveBid {
        bytes32 a_id;
        bytes32 b_id;
        address payable bidder;
        uint256 marketplaceFee;
        uint256 price;
        uint256 startingAt;
        uint256 expiredAt;
    }

    struct Auction {
        uint256 saleType;
        bytes32 a_id;
        address payable seller;
        address creator;
        address partner;
        uint256 price;
        uint256 endingPrice;
        uint256 startingAt;        
        uint256 expiredAt;
        AuctionStatus status;
    }

    struct RoyaltySettings {
        IERC721Creator iErc721CreatorContract;
        uint256 percentage;
    }

    uint256 private marketplaceFeePercentage;
    uint256 private partnerFeePercentage;
    uint256 private creatorFeePercentage;
    
    uint256 private constant AUCTION    = 1;
    uint256 private constant BUYNOW     = 2;

    uint256 constant maximumPercentage = 1000;
    uint256 public constant maximumMarketValue = 2**255;
    uint256 public minimumBidIncreasePercentage = 10; // 1% -- 100 = 10%

    // MarketplaceSettings public marketplaceFeeSet = MarketplaceSettings(0, 25);

    enum AuctionStatus {
        Live,
        Closed,
        Canceled
    }

    mapping(address => uint8) private primarySaleFees;
    mapping(address => mapping(uint256 => Auction)) private tokenPrices;
    mapping(address => mapping(uint256 => bool)) private soldTokens;
    mapping(address => mapping(uint256 => ActiveBid)) private tokenCurrentBids;
    mapping(address => RoyaltySettings) private contractRoyaltySettings;
    mapping(address => uint256) private contractPrimarySaleFee;
    mapping(address => mapping(uint256 => uint256)) private tokenRoyaltyPercentage;
    mapping(address => uint256) private creatorRoyaltyPercentage;
    mapping(address => uint256) private contractRoyaltyPercentage;


    event Sold(
        uint256 _type,
        bytes32 _a_id,
        address indexed _tokenAddress,
        address indexed _buyer,
        address indexed _seller,
        uint256 _amount,
        uint256 _tokenId
        // uint256 _startingAt,
        // uint256 _expiredAt
    );

    event CreateOrder(
        uint256 _type,
        bytes32 _a_id,
        address indexed _seller,
        address indexed _tokenAddress,
        uint256 _startingPrice,
        uint256 _tokenId,
        uint256 _startingAt,
        uint256 _expiredAt
    );

    event Bid(
        bytes32 _a_id,
        bytes32 _b_id,
        address indexed _seller,
        uint256 _startPrice,
        address indexed _tokenAddress,
        address indexed _bidder,
        uint256 _amount,
        uint256 _tokenId
    );

    event AcceptBid(
        bytes32 _a_id,
        bytes32 _b_id,
        address indexed _seller,
        uint256 _startPrice,
        address indexed _tokenAddress,
        address indexed _bidder,
        uint256 _amount,
        uint256 _tokenId
        // uint256 _expiredAt
    );

    event CancelBid(
        bytes32 _a_id,
        bytes32 _b_id,
        address indexed _seller,
        uint256 _startPrice,
        address indexed _tokenAddress,
        address indexed _bidder,
        uint256 _amount,
        uint256 _tokenId
        // uint256 _expiredAt
    );


    // event CancelOrder(
    //     bytes32 _a_id,
    //     address indexed _tokenAddress,
    //     uint256 _tokenId
    // );

    event CancelOrder(
        uint256 _type,
        bytes32 _a_id,
        address indexed _seller,
        address indexed _tokenAddress,
        uint256 _amount,
        uint256 _tokenId
        // uint256 _expiredAt
    );    

    event ForceClose(
        uint256 _type,
        bytes32 _a_id,
        address indexed _seller,
        address indexed _tokenAddress,
        uint256 _amount,
        uint256 _tokenId
        // uint256 _expiredAt
    );    


    event RoyaltySettingsSet(
        address indexed _erc721CreatorContract,
        uint256 _percentage
    );

    event PrimarySalePercentageSet(
        address indexed _tokenAddress,
        uint256 _percentage
    );

    address private maintainer;

    constructor(address _maintainer) {
        maintainer = _maintainer;
        partnerFeePercentage = 300; // 30% partner fee on all txs.
        marketplaceFeePercentage = 100; // 10% marketplace fee on all txs.
        creatorFeePercentage = 600; // 60% creator calc price.
    }

    function getPartnerFeePercentage() public view returns (uint256) {
        return partnerFeePercentage;
    }

    function setPartnerFeePercentage(uint256 _percentage) public onlyOwner {
        require( _percentage <= 100, "setPartnerFeePercentage::_percentage must be <= 100");
        partnerFeePercentage = _percentage * 10;
    }
 
    function getMarketplaceFeePercentage() public view returns (uint256) {
        return marketplaceFeePercentage;
    }

    function setMarketplaceFeePercentage(uint256 _percentage) public onlyOwner {
        require( _percentage <= 100, "setMarketplaceFeePercentage::_percentage must be <= 100");
        marketplaceFeePercentage = _percentage * 10;
    }
    
    function getCreatorFeePercentage() public view returns (uint256) {
        return creatorFeePercentage;
    }

    function setCreatorFeePercentage(uint256 _percentage) public onlyOwner {
        require( _percentage <= 100, "setCreatorFeePercentage::_percentage must be <= 100");
        creatorFeePercentage = _percentage * 10;
    }

    function getERC721ContractPrimarySaleFeePercentage(address _contractAddress) public view returns (uint256) {
        return primarySaleFees[_contractAddress];
    }

    function setERC721ContractPrimarySaleFeePercentage( address _contractAddress, uint8 _percentage ) public onlyOwner {
        require( _percentage <= 1000, "setERC721ContractPrimarySaleFeePercentage::_percentage must be <= 1000");
        primarySaleFees[_contractAddress] = _percentage;
    }

    function setMinimumBidIncreasePercentage(uint8 _percentage) public onlyOwner {
        minimumBidIncreasePercentage = _percentage;
    }    

    function ownerMustHaveMarketplaceApproved( address _tokenAddress, uint256 _tokenId ) internal view {
        IERC721 erc721 = IERC721(_tokenAddress);
        address owner = erc721.ownerOf(_tokenId);
        require( erc721.isApprovedForAll(owner, address(this)), "owner must have approved contract");
    }

    function senderMustBeTokenOwner(address _tokenAddress, uint256 _tokenId) internal view {
        IERC721 erc721 = IERC721(_tokenAddress);
        require( erc721.ownerOf(_tokenId) == msg.sender, "sender must be the token owner");
    }

    function createBuyNow( address _tokenAddress, uint256 _tokenId, uint256 _price, uint256 _startingAt, uint256 _expiredAt, address _creator, address _partner) external {
        if(_startingAt <= block.timestamp) {
            _createOrder( BUYNOW, _tokenAddress, _tokenId, _price, _price, block.timestamp, _expiredAt, _creator, _partner);
        }
        else {
            _createOrder( BUYNOW, _tokenAddress, _tokenId, _price, _price, _startingAt, _expiredAt, _creator, _partner);
        }
        
    }

    function createAuction( address _tokenAddress, uint256 _tokenId, uint256 _price, uint256 _endingPrice, uint256 _startingAt, uint256 _expiredAt, address _creator, address _partner) external {
        require( !_tokenHasBid(_tokenAddress, _tokenId ), "createOrder::Order already exists");
        _createOrder( AUCTION, _tokenAddress, _tokenId, _price, _endingPrice, _startingAt, _expiredAt, _creator, _partner);
    }

    function _createOrder( uint256 _type, address _tokenAddress, uint256 _tokenId, uint256 _price, uint256 _endingPrice, uint256 _startingAt, uint256 _expiredAt, address _creator, address _partner) internal {
        ownerMustHaveMarketplaceApproved(_tokenAddress, _tokenId);
        senderMustBeTokenOwner(_tokenAddress, _tokenId);
        require(_price > 0, "createOrder::Price should be bigger than 0");
        require( _price <= maximumMarketValue, "createOrder::Cannot set sale price larger than max value" );
        require( _startingAt < _expiredAt, "createOrder::Cannot _startingAt larger than _expiredAt" );

        bytes32 _orderId = keccak256(abi.encodePacked(block.timestamp, msg.sender, _tokenAddress, _tokenId, _price));
        
        tokenPrices[_tokenAddress][_tokenId] = Auction(_type, _orderId, payable(msg.sender), _creator, _partner, _price, _endingPrice, _startingAt, _expiredAt, AuctionStatus.Live);
        emit CreateOrder(_type, _orderId, msg.sender, _tokenAddress, _price, _tokenId, _startingAt, _expiredAt);
    }

    function cancelOrder(address _tokenAddress, uint256 _tokenId) external payable {
        require(tokenPrices[_tokenAddress][_tokenId].seller == msg.sender, "cancelOrder::seller only can cancel order.");
        Auction memory sp = tokenPrices[_tokenAddress][_tokenId];
        _closeOrder(_tokenAddress, _tokenId);
        emit CancelOrder(sp.saleType, sp.a_id, sp.seller, _tokenAddress, sp.price, _tokenId);
    }

    function forceClose(address _tokenAddress, uint256 _tokenId) external payable onlyOwner{
        Auction memory sp = tokenPrices[_tokenAddress][_tokenId];
        _closeOrder(_tokenAddress, _tokenId);
        // emit ForceClose(sp.a_id, _tokenAddress, _tokenId);   
        emit ForceClose(sp.saleType, sp.a_id, sp.seller, _tokenAddress, sp.price, _tokenId);
    }

    function _closeOrder(address _tokenAddress, uint256 _tokenId) private {
        if(_tokenHasBid(_tokenAddress, _tokenId )) {
            _refundBid(_tokenAddress, _tokenId);
        }
        _resetTokenPrice(_tokenAddress, _tokenId, AuctionStatus.Closed);
    }

    function buy(address _tokenAddress, uint256 _tokenId) public payable {
        ownerMustHaveMarketplaceApproved(_tokenAddress, _tokenId);
        require(_priceSetterStillOwnsTheToken(_tokenAddress, _tokenId),"buy::Current token owner must be the person to have the latest price.");

        Auction memory sp = tokenPrices[_tokenAddress][_tokenId];
        require(sp.price > 0, "buy::Tokens priced at 0 are not for sale.");
        require(sp.price == msg.value,"buy::Must purchase the token for the correct price");
        require(sp.startingAt <= block.timestamp, "buy::startingAt is larger than block.timestamp.");
        require(sp.saleType == BUYNOW, "buy::Auction mode does not support this func.");
        require(sp.creator != address(0), "payout::invalidate creator address");
        require(sp.partner != address(0), "payout::invalidate partner address");

        IERC721 erc721 = IERC721(_tokenAddress);
        address tokenOwner = erc721.ownerOf(_tokenId);
        erc721.safeTransferFrom(tokenOwner, msg.sender, _tokenId);
        _resetTokenPrice(_tokenAddress, _tokenId, AuctionStatus.Closed);
        _setTokenAsSold(_tokenAddress, _tokenId);

        _payout(sp.price, sp.creator, sp.partner);
        emit Sold(sp.saleType, sp.a_id, _tokenAddress, msg.sender, tokenOwner, sp.price, _tokenId);
    }

    function tokenPrice(address _tokenAddress, uint256 _tokenId) external view returns (uint256) {
        ownerMustHaveMarketplaceApproved(_tokenAddress, _tokenId);
        if (_priceSetterStillOwnsTheToken(_tokenAddress, _tokenId)) {
            return tokenPrices[_tokenAddress][_tokenId].price;
        }
        return 0;
    }

    function bid( address _tokenAddress, uint256 _tokenId, uint256 _newBidprice) external payable {
        Auction memory sp = tokenPrices[_tokenAddress][_tokenId];
        require(block.timestamp >= sp.startingAt, "bid:: not started.");
        require(block.timestamp < sp.expiredAt, "bid:: already expired.");
        require(sp.saleType == AUCTION, "buy::Buy Now mode does not support this func.");
        require(_newBidprice > 0, "bid::Cannot bid 0 Wei.");
        require(_newBidprice == msg.value,"buy::Must purchase the token for the correct price");
        require(_newBidprice <= maximumMarketValue, "bid::Cannot bid higher than max value");
        if (sp.endingPrice > 0) {
            require(_newBidprice <= sp.endingPrice, "bid::Overflow ending price");
        }
        
        uint256 currentBidprice = tokenCurrentBids[_tokenAddress][_tokenId].price;
        
        if (_newBidprice == sp.endingPrice) {
            // 즉시 구매 (AcceptBid)
            _refundBid(_tokenAddress, _tokenId);

            IERC721 erc721 = IERC721(_tokenAddress);
            address tokenOwner = erc721.ownerOf(_tokenId);
            erc721.safeTransferFrom(tokenOwner, msg.sender, _tokenId);

            _resetTokenPrice(_tokenAddress, _tokenId, AuctionStatus.Closed);
            _setTokenAsSold(_tokenAddress, _tokenId);
            _payout(sp.endingPrice, sp.creator, sp.partner);

            emit AcceptBid(sp.a_id, 0, sp.seller, sp.price, _tokenAddress, msg.sender, _newBidprice, _tokenId);
            
        } else {
            // 비딩 (Bid)
            require( _newBidprice > currentBidprice, "bid::Must place higher bid than existing bid.");
             // Must bid higher than current bid.
            require( _newBidprice > currentBidprice && _newBidprice >= currentBidprice.add( currentBidprice.mul(minimumBidIncreasePercentage).div(1000)), "bid::must bid higher than previous bid + minimum percentage increase.");
            
            bytes32 _bidId = keccak256(
                abi.encodePacked(
                    block.timestamp,
                    msg.sender,
                    sp.a_id,
                    _newBidprice,
                    sp.expiredAt
                )
            );
    
            IERC721 erc721 = IERC721(_tokenAddress);
            address tokenOwner = erc721.ownerOf(_tokenId);
            require(tokenOwner != msg.sender, "bid::Bidder cannot be owner.");
            _refundBid(_tokenAddress, _tokenId);
            _setBid(sp.a_id, _bidId, _newBidprice, payable(msg.sender), _tokenAddress, _tokenId, sp.startingAt, sp.expiredAt);
    
            emit Bid(sp.a_id, _bidId, sp.seller, sp.price, _tokenAddress, msg.sender, _newBidprice, _tokenId);
        }
    }

    function getBlockTime() public view returns (uint256) {
        return block.timestamp;
    } 

    function acceptBid(address _tokenAddress, uint256 _tokenId) public {
        Auction memory sp = tokenPrices[_tokenAddress][_tokenId];
        require(sp.saleType == AUCTION, "buy::Buy Now mode  does not support this func.");
        
        ownerMustHaveMarketplaceApproved(_tokenAddress, _tokenId);
        senderMustBeTokenOwner(_tokenAddress, _tokenId);
        
        require( _tokenHasBid(_tokenAddress, _tokenId), "acceptBid::Cannot accept a bid when there is none.");        
        require(sp.expiredAt < block.timestamp);
        require(sp.creator != address(0), "payout::invalidate creator address");
        require(sp.partner != address(0), "payout::invalidate partner address");

        ActiveBid memory currentBid = tokenCurrentBids[_tokenAddress][_tokenId];
        
        IERC721 erc721 = IERC721(_tokenAddress);
        erc721.safeTransferFrom(msg.sender, currentBid.bidder, _tokenId);
        
        _payout(currentBid.price, sp.creator, sp.partner);
        
        _resetTokenPrice(_tokenAddress, _tokenId, AuctionStatus.Closed);
        _resetBid(_tokenAddress, _tokenId);
        _setTokenAsSold(_tokenAddress, _tokenId);
        emit AcceptBid(currentBid.a_id, currentBid.b_id, sp.seller, sp.price, _tokenAddress, currentBid.bidder, currentBid.price, _tokenId);
    }

    function cancelBid(address _tokenAddress, uint256 _tokenId) external {
        Auction memory sp = tokenPrices[_tokenAddress][_tokenId];
        ActiveBid memory currentBid = tokenCurrentBids[_tokenAddress][_tokenId];
        require(sp.saleType == AUCTION, "buy::Buy Now mode does not support this func.");
        require(_checkBidder(msg.sender, _tokenAddress, _tokenId),"cancelBid::Cannot cancel a bid if sender hasn't made one.");
        _refundBid(_tokenAddress, _tokenId);
        emit CancelBid(currentBid.a_id, currentBid.b_id, sp.seller, sp.price, _tokenAddress,msg.sender,tokenCurrentBids[_tokenAddress][_tokenId].price,_tokenId);
    }

    function getCurrentBid(address _tokenAddress, uint256 _tokenId) public view returns (uint256, address) {
        return (tokenCurrentBids[_tokenAddress][_tokenId].price, tokenCurrentBids[_tokenAddress][_tokenId].bidder);
    }

    function getOrderInfo(address _tokenAddress, uint256 _tokenId) public view returns (uint256, address, uint256, uint256, uint256, address, address) {
        Auction memory sp = tokenPrices[_tokenAddress][_tokenId];
        return (sp.saleType, sp.seller, sp.price, sp.endingPrice, sp.expiredAt, sp.creator, sp.partner);
    }

    function hasTokenBeenSold(address _tokenAddress, uint256 _tokenId) external view returns (bool) {
        return soldTokens[_tokenAddress][_tokenId];
    }

    function _priceSetterStillOwnsTheToken( address _tokenAddress, uint256 _tokenId ) internal view returns (bool) {
        IERC721 erc721 = IERC721(_tokenAddress);
        return erc721.ownerOf(_tokenId) == tokenPrices[_tokenAddress][_tokenId].seller;
    }

    function _payout( uint256 _amount, address _creatorAddress, address _partnerAddress) private {
        uint256[4] memory payments;
        
        // uint256 marketplaceFee
        payments[0] = calcPercentagePayment(_amount, getMarketplaceFeePercentage());
        
        // unit256 creatorFee
        payments[1] = calcPercentagePayment(_amount, getCreatorFeePercentage());

        // unit256 partnerFee
        payments[2] = calcPercentagePayment(_amount, getPartnerFeePercentage());

        // marketplacePayment
        if (payments[0] > 0) {
            sendMoneyOrEscrow(_makePayable(maintainer), payments[0]);
        }
        // creatorPayment
        if (payments[1] > 0) {
            require(_creatorAddress != address(0), "payout::invalidate creator address");
            sendMoneyOrEscrow(_makePayable(_creatorAddress), payments[1]);
        }
        // partnerPayment
        if (payments[2] > 0) {
            require(_partnerAddress != address(0), "payout::invalidate partner address");
            sendMoneyOrEscrow(_makePayable(_partnerAddress), payments[2]);
        }
    }

    function calcPercentagePayment(uint256 _amount, uint256 _percentage) internal pure returns (uint256) {
        return _amount.mul(_percentage).div(1000);
    }

    function _setTokenAsSold(address _tokenAddress, uint256 _tokenId) internal {
        if (soldTokens[_tokenAddress][_tokenId]) {
            return;
        }
        soldTokens[_tokenAddress][_tokenId] = true;
    }

    function _resetTokenPrice(address _tokenAddress, uint256 _tokenId, AuctionStatus _status) internal {
        tokenPrices[_tokenAddress][_tokenId] = Auction(0, 0, payable(address(0)), address(0), address(0), 0, 0, 0, 0, _status);
    }

    function _checkBidder( address _bidder, address _tokenAddress, uint256 _tokenId ) internal view returns (bool) {
        return tokenCurrentBids[_tokenAddress][_tokenId].bidder == _bidder;
    }

    function _tokenHasBid(address _tokenAddress, uint256 _tokenId) internal view returns (bool) {
        return tokenCurrentBids[_tokenAddress][_tokenId].bidder != address(0);
    }

    function _refundBid(address _tokenAddress, uint256 _tokenId) internal {
        ActiveBid memory currentBid = tokenCurrentBids[_tokenAddress][_tokenId];
        if (currentBid.bidder == address(0)) {
            return;
        }
        
        _resetBid(_tokenAddress, _tokenId);
        sendMoneyOrEscrow(currentBid.bidder, currentBid.price);
    }

    function _resetBid(address _tokenAddress, uint256 _tokenId) internal { 
        tokenCurrentBids[_tokenAddress][_tokenId] = ActiveBid(0, 0, payable(address(0)),0,0,0,0);
    }

    function _setBid( bytes32 _aucId,  bytes32 _bidId, uint256 _price, address payable _bidder, address _tokenAddress, uint256 _tokenId, uint256 _startingAt, uint256 _expiredAt) internal {
        require(_bidder != address(0), "Bidder cannot be 0 address.");
        tokenCurrentBids[_tokenAddress][_tokenId] = ActiveBid(_aucId, _bidId, _bidder, getMarketplaceFeePercentage(), _price, _startingAt, _expiredAt);
    }

    function _makePayable(address _address) internal pure returns (address payable) {
        return payable(address(uint160(_address)));
    }
}