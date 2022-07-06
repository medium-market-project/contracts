// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./MIP721.sol";
import "./MediumAccessControl.sol";

contract MediumMarket is MediumAccessControl, Pausable {
    
    using SafeMath for uint;

    enum SaleType { BUY_NOW, AUCTION }

    struct SaleDocument {
        SaleType saleType;      // 즉시구매 / 경매
        uint marketKey;         // 서비스에서 생성한 판매 키
        address seller;         // 판매자
        address nftContract;    // 판매 NFT컨트랙트
        bool isLazyMint;        // lazy mint 여부
        string metaUri;             // lazy mint 일때 토큰 uri
        uint tokenId;           // 판매 토큰 아이디 (lazy mint일 경우 값이 없다)
        uint collectionKey;     // 서비스에서 생성한 컬렉션 키
        address originator;     // 원작자
        uint startPrice;        // 판매 시작가 (즉시구매 타입일 경우 판매 시작가는 즉시 구매가와 동일하게 셋팅. 경매 타입일 경우 입찰 시작가)
        uint buyNowPrice;       // 즉시 구매가 (즉시구매 타입일 경우 판매가. 경매 타입일 경우 0x0이면 즉시구매가 없음을 의미)
        address bidder;         // 현재 입찰자
        uint bidPrice;          // 현재 입찰가
        uint bidCount;          // 현재까지의 입찰 수
        uint startTime;         // 판매/경매 시작 시간
        uint endTime;           // 판매/경매 종료 시간
        uint metaHash;          // meta file hash. 판매 등록 시점의 메타파일과 판매 완료 시점의 메타파일의 동일성을 제공할 필요가 있는 경우 사용. 사용하지 않을때는 0으로.
        bool onSale;            // 판매 도큐먼트의 유효 플랙. 종결시 delete가 기준이나 예외 경우를 위한 보조 필드.

        address[] payoutAddresses;  // ex; [seller, orginator, market]
        uint[] payoutRatios;        // ex; [850(85%), 50(5%), 100(10%)]
        uint minBidIncrPercent;     // ex; 50(5%)
    }

    mapping(uint => SaleDocument) _salesBook;   // 판매 대기 또는 판매중인 판매정보 목록. 판매 완료되거나 판매 기간 종료시 삭제.

    event CreateSale(SaleType saleType, uint indexed marketKey, address indexed seller, address indexed nftContract, bool isLazyMint, string metaUri, uint tokenId, uint collectionKey, address originator, uint startPrice, uint buyNowPrice, uint startTime, uint endTime);
    event Buy(SaleType saleType, uint indexed marketKey, address indexed buyer, address indexed nftContract, address seller, uint tokenId, uint collectionKey, address originator, uint price);
    event Bid(SaleType saleType, uint indexed marketKey, address seller, address indexed nftContract, bool isLazyMint, string metaUri, uint tokenId, uint collectionKey, address indexed bidder, uint bidPrice, uint bidCount);
    event AcceptBid(SaleType saleType, uint indexed marketKey, address seller, address indexed nftContract, uint tokenId, uint collectionKey, address originator, address indexed bidder, uint bidPrice, uint bidCount);
    event CancelSale(SaleType saleType, uint indexed marketKey, address indexed seller, address indexed nftContract, bool isLazyMint, string metaUri, uint tokenId, uint collectionKey, address originator);
    event ForceCloseSale(SaleType saleType, uint indexed marketKey, address indexed seller, address indexed nftContract, bool isLazyMint, string metaUri, uint tokenId, uint collectionKey, address originator, address bidder, uint bidPrice, uint bidCount);
    event RefundBid(SaleType saleType, uint indexed marketKey, address seller, address indexed nftContract, bool isLazyMint, string metaUri, uint tokenId, uint collectionKey, address originator, address indexed bidder, uint bidPrice);
    event Payment(SaleType saleType, uint indexed marketKey, address seller, address indexed nftContract, uint tokenId, uint collectionKey, address originator, uint price, address[] payoutAddresses, uint[] payoutRatios, uint[] payoutValues);

    function pause() public onlyAdmin {
        _pause();
    }

    function unpause() public onlyAdmin {
        _unpause();
    }
    
    //uint[] buyNowSaleInfo = [isLazyMint, tokenId, collectionKey, buyNowPrice, startTime, endTime, metaHash];
    function createBuyNow(uint marketKey, address seller, address nftContract, address originator, uint[7] calldata buyNowSaleInfo, string calldata metaUri, address[] calldata payoutAddresses, uint[] calldata payoutRatios) external whenNotPaused {
        // 판매자의 호출을 기준으로 함
        require (seller == msg.sender, "invalid seller");
        
        SaleDocument memory doc;
        doc.saleType = SaleType.BUY_NOW;
        doc.marketKey = marketKey;
        doc.seller = seller;
        doc.nftContract = nftContract;
        doc.originator = originator;
        doc.isLazyMint = buyNowSaleInfo[0] != 0;
        doc.tokenId = buyNowSaleInfo[1];
        doc.collectionKey = buyNowSaleInfo[2];
        doc.startPrice = buyNowSaleInfo[3];
        doc.buyNowPrice = buyNowSaleInfo[3];
        doc.startTime = (buyNowSaleInfo[4] > block.timestamp ? buyNowSaleInfo[4] : block.timestamp);
        doc.endTime = buyNowSaleInfo[5];
        doc.metaHash = buyNowSaleInfo[6];
        doc.metaUri = metaUri;
        doc.payoutAddresses = payoutAddresses;
        doc.payoutRatios = payoutRatios;

        _createSale(doc);
    }

    //uint[] auctionSaleInfo = [isLazyMint, tokenId, collectionKey, startPrice, buyNowPrice, startTime, endTime, minBidIncrPercent, metaHash];
    function createAuction(uint marketKey, address seller, address nftContract,address originator, uint[9] calldata auctionSaleInfo, string calldata metaUri, address[] calldata payoutAddresses, uint[] calldata payoutRatios) external whenNotPaused {
        // 판매자의 호출을 기준으로 함
        require (seller == msg.sender, "invalid seller");

        SaleDocument memory doc;
        doc.saleType = SaleType.AUCTION;
        doc.marketKey = marketKey;
        doc.seller = seller;
        doc.nftContract = nftContract;
        doc.originator = originator;
        doc.isLazyMint = auctionSaleInfo[0] != 0;
        doc.tokenId = auctionSaleInfo[1];
        doc.collectionKey = auctionSaleInfo[2];
        doc.startPrice = auctionSaleInfo[3];
        doc.buyNowPrice = auctionSaleInfo[4];
        doc.startTime = (auctionSaleInfo[5] > block.timestamp ? auctionSaleInfo[5] : block.timestamp);
        doc.endTime = auctionSaleInfo[6];
        doc.minBidIncrPercent = auctionSaleInfo[7];
        doc.metaHash = auctionSaleInfo[8];
        doc.metaUri = metaUri;
        doc.payoutAddresses = payoutAddresses;
        doc.payoutRatios = payoutRatios;

        _createSale(doc);
    }

    function cancelSale(uint marketKey) external {
        // 판매자가 호출. 입찰자가 있는 상태에서는 불가능
        SaleDocument memory doc = _salesBook[marketKey];
        require (doc.onSale, "market key : not on sale");
        require (doc.seller == msg.sender, "only seller can cancel");
        require (doc.bidder == address(0), "bid exist");

        emit CancelSale(doc.saleType, doc.marketKey, doc.seller, doc.nftContract, doc.isLazyMint, doc.metaUri, doc.tokenId, doc.collectionKey, doc.originator);

        _closeSale(marketKey);
    }

    function forceCloseSale(uint marketKey) public onlyAdmin {
        // 시스템에서 호출. 입찰자가 있는 상태에서도 가능
        SaleDocument memory doc = _salesBook[marketKey];
        require (doc.onSale, "market key : not on sale");

        emit ForceCloseSale(doc.saleType, doc.marketKey, doc.seller, doc.nftContract, doc.isLazyMint, doc.metaUri, doc.tokenId, doc.collectionKey, doc.originator, doc.bidder, doc.bidPrice, doc.bidCount);

        _closeSale(marketKey);
    }

    function buy(uint marketKey, uint price, uint metaHash) external payable whenNotPaused {
        // 구매자가 호출. 구매자가 수수료 부담. 레이지민트일 경우 민팅 비용까지도 구매자가 부담. 판매자도 구매 가능

        SaleDocument memory doc = _salesBook[marketKey];
        require (doc.onSale, "market key : not on sale");
        if (doc.endTime != 0) {
            require (doc.startTime <= block.timestamp && block.timestamp <= doc.endTime, "not on sale time");
        }
        require (doc.buyNowPrice == price && price == msg.value, "transfered value must match the price");
        require (doc.metaHash == metaHash, "meta hash changed");

        if (doc.metaHash > 0 && !doc.isLazyMint) {
            _callNFTRemoveSnapsot(doc.nftContract, doc.tokenId);
        }

        if (doc.isLazyMint) {
            doc.tokenId = _callNFTMint(doc.nftContract, msg.sender, doc.metaUri);
        } else {
            _callNFTTransfer(doc.nftContract, doc.tokenId, doc.seller, msg.sender);
        }
        
        uint[] memory payoutValues = _payout(price, doc.payoutAddresses, doc.payoutRatios);
        emit Payment(doc.saleType, doc.marketKey, doc.seller, doc.nftContract, doc.tokenId, doc.collectionKey, doc.originator, price, doc.payoutAddresses, doc.payoutRatios, payoutValues);

        emit Buy(doc.saleType, doc.marketKey, msg.sender, doc.nftContract, doc.seller, doc.tokenId, doc.collectionKey, doc.originator, price);

        delete(_salesBook[marketKey]);
    }

    function bid(uint marketKey, uint price, uint metaHash) external payable whenNotPaused {
        // 입찰자가 호출. 입찰자가 수수료 부담. 레이지민트일 경우 민팅 비용까지도 구매자가 부담.
        // 판매자도 입찰 가능

        SaleDocument memory doc = _salesBook[marketKey];
        require (doc.onSale, "market key : not on sale");
        require (doc.startTime <= block.timestamp && block.timestamp <= doc.endTime, "not on sale time");
        require (price == msg.value, "transfered value must match the price");
        require (doc.metaHash == metaHash, "meta hash changed");

        if (doc.bidder == address(0)) {
            require (doc.startPrice <= price, "transfered value must be equal or greater than the start price");
        } else {
            require (doc.bidPrice.mul(doc.minBidIncrPercent.add(1000)).div(1000) <= price, "transfered value must be greater than current minimum bid price");
        }

        if (doc.bidder != address(0)) {
            _refundBid(doc.bidder, doc.bidPrice);
            
            emit RefundBid(doc.saleType, doc.marketKey, doc.seller, doc.nftContract, doc.isLazyMint, doc.metaUri, doc.tokenId, doc.collectionKey, doc.originator, doc.bidder, doc.bidPrice);
        }

        doc.bidPrice = price;
        doc.bidder = msg.sender;
        doc.bidCount += 1;

        _salesBook[marketKey] = doc;

        emit Bid(doc.saleType, doc.marketKey, doc.seller, doc.nftContract, doc.isLazyMint, doc.metaUri, doc.tokenId, doc.collectionKey, doc.bidder, doc.bidPrice, doc.bidCount);

        if (doc.buyNowPrice > 0 && doc.buyNowPrice <= price) {
            _acceptBid(doc.marketKey, metaHash);
        }
    }

    function acceptBid(uint marketKey, uint metaHash) external onlyAdmin {
        _acceptBid(marketKey, metaHash);
    }
    
    function _acceptBid(uint marketKey, uint metaHash) internal {
        // 마켓시스템 호출. 시간이 되면 자동으로 낙찰처리. 또는 경매에서 즉시구매가가 되었을때 실행.

        SaleDocument memory doc = _salesBook[marketKey];
        require (doc.onSale, "market key : not on sale");
        require (doc.saleType == SaleType.AUCTION, "not auction type");
        require (doc.metaHash == metaHash, "meta hash changed");

        if (doc.metaHash > 0 && !doc.isLazyMint) {
            _callNFTRemoveSnapsot(doc.nftContract, doc.tokenId);
        }

        if (doc.bidder != address(0)) {
            if (doc.isLazyMint) {
                doc.tokenId = _callNFTMint(doc.nftContract, doc.bidder, doc.metaUri);
            } else {
                _callNFTTransfer(doc.nftContract, doc.tokenId, doc.seller, doc.bidder);
            }
            
            uint[] memory payoutValues = _payout(doc.bidPrice, doc.payoutAddresses, doc.payoutRatios);

            emit Payment(doc.saleType, doc.marketKey, doc.seller, doc.nftContract, doc.tokenId, doc.collectionKey, doc.originator, doc.bidPrice, doc.payoutAddresses, doc.payoutRatios, payoutValues);
        }

        emit AcceptBid(doc.saleType, doc.marketKey, doc.seller, doc.nftContract, doc.tokenId, doc.collectionKey, doc.originator, doc.bidder, doc.bidPrice, doc.bidCount);

        delete(_salesBook[marketKey]);
    }

    function _createSale(SaleDocument memory doc) internal {
        require (_salesBook[doc.marketKey].onSale == false, "market key : already exist");
        require (doc.seller != address(0), "invalid seller address");
        require (doc.nftContract != address(0), "invalid nft contract address");
        if (doc.saleType != SaleType.BUY_NOW || doc.endTime != 0) {
            require (doc.endTime > doc.startTime && doc.endTime > block.timestamp, "invalid endTime");
        }
        require (doc.isLazyMint || (doc.seller == _getTokenOwner(doc.nftContract, doc.tokenId)), "not token owner");
        require (_isTokenApprovedForAll(doc.nftContract, doc.seller), "not approved");

        if (doc.metaHash != 0 && !doc.isLazyMint) {
            _callNFTSaveSnapsot(doc.nftContract, doc.tokenId, doc.metaHash);
        }
        
        doc.onSale = true;
        _salesBook[doc.marketKey] = doc;

        emit CreateSale(doc.saleType, doc.marketKey, doc.seller, doc.nftContract, doc.isLazyMint, doc.metaUri, doc.tokenId,
            doc.collectionKey, doc.originator, doc.startPrice, doc.buyNowPrice,
            doc.startTime, doc.endTime);
    }

    function _closeSale(uint marketKey) internal {
        SaleDocument memory doc = _salesBook[marketKey];
        if (doc.onSale) {
            if (doc.saleType == SaleType.AUCTION && doc.bidder != address(0)) {
                _refundBid(doc.bidder, doc.bidPrice);
                
                emit RefundBid(doc.saleType, doc.marketKey, doc.seller, doc.nftContract, doc.isLazyMint, doc.metaUri, doc.tokenId, doc.collectionKey, doc.originator, doc.bidder, doc.bidPrice);
            }

            if (doc.metaHash != 0) {
                _callNFTRemoveSnapsot(doc.nftContract, doc.tokenId);
            }
        }
        delete(_salesBook[marketKey]);
    }

    function _refundBid(address bidder, uint bidPrice) internal {
        if (bidder != address(0)) {
            payable(bidder).transfer(bidPrice);
        }
    }

    function _payout(uint payoutPrice, address[] memory payoutAddresses, uint[] memory payoutRatios) internal returns (uint[] memory) {
        require(address(this).balance >= payoutPrice, "Depository balance is not enough to payout");
        require(payoutAddresses.length == payoutRatios.length, "payout pair must match");

        if (payoutPrice > 0 && payoutAddresses.length > 0) {
            uint payoutRatioSum = 0;
            uint[] memory payoutValues = new uint[] (payoutAddresses.length);
            for (uint i = 0; i < payoutAddresses.length; i++) {
                payoutRatioSum += payoutRatios[i];
            }
            for (uint i = 0; i < payoutAddresses.length; i++) {
                if (payoutRatios[i] > 0) {
                    uint payoutVal = payoutPrice.mul(payoutRatios[i]).div(payoutRatioSum);
                    payoutValues[i] = payoutVal;
                    payable(payoutAddresses[i]).transfer(payoutVal);
                } else {
                    payoutValues[i] = 0;
                }
            }
            return payoutValues;
        }
        return new uint[](0);
    }


    function _isTokenApprovedForAll(address nftContract, address owner) internal view returns (bool) {
        IERC721 erc721 = IERC721(nftContract);
        return erc721.isApprovedForAll(owner, address(this));
    }

    function _getTokenOwner(address nftContract, uint256 tokenId) internal view returns (address) {
        IERC721 erc721 = IERC721(nftContract);
        return erc721.ownerOf(tokenId);
    }

    function _callNFTTransfer(address nftContract, uint tokenId, address from, address to) internal {
        IERC721 erc721 = IERC721(nftContract);
        address owner = erc721.ownerOf(tokenId);
        require (owner == from, "owner not match");
        erc721.safeTransferFrom(from, to, tokenId);
    }

   function _callNFTMint(address nftContract, address to, string memory uri) internal returns (uint) {
        MIP721 mip721 = MIP721(nftContract);
        return mip721.mint(to, uri);
    }

    function _callNFTSaveSnapsot(address nftContract, uint tokenId, uint hashValue) internal {
        MIP721 mip721 = MIP721(nftContract);
        mip721.snapshot(tokenId, hashValue);
    }

    function _callNFTRemoveSnapsot(address nftContract, uint tokenId) internal {
        MIP721 mip721 = MIP721(nftContract);
        mip721.removeSnapshot(tokenId);
    }
}
