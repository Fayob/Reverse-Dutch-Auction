// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

error TRANSFER_FAILED();
error INSUFFICIENT_BALANCE();
error INSUFFICIENT_ALLOWANCE();
error INVALID_ADDRESS();
error PERIOD_MUST_BE_HIGHER_THAN_ZERO();
error AMOUNT_MUST_BE_HIGHER_THAN_END_AMOUNT();
error AMOUNT_MUST_BE_HIGHER_THAN_ZERO();
error AUCTION_HAS_ENDED();
error CANNOT_BUY_AUCTION_OWNED_BY_YOU();
error AUCTION_COMPLETED();
error INACTIVE_AUCTION();
error AUCTION_FINALIZED();
error ONLY_SELLER_CANCEL();
error INVALID_ID();

contract ReverseDutchAuctionSwap {
    bool private locked;
    
    modifier noReentrant() {
        require(!locked, "No reentrancy");
        locked = true;
        _;
        locked = false;
    }

    struct Auction {
        address seller;
        address tokenAddress;
        uint256 tokenAmount;
        uint256 startPrice;
        uint256 endPrice;
        uint256 startTime;
        uint256 duration;
        bool active;
        bool finalized;
    }

    Auction[] public auctions;

    event AuctionFinalized(
        uint256 indexed auctionId,
        address buyer,
        uint256 price
    );

    event AuctionCreated(
        uint256 indexed auctionId,
        address seller,
        address tokenAddress,
        uint256 tokenAmount,
        uint256 startPrice,
        uint256 endPrice,
        uint256 duration
    );

    event AuctionCancelled(
        uint256 indexed auctionId,
        address seller
    );

    function createAuction(
        address tokenAddress,
        uint256 tokenAmount,
        uint256 startPrice,
        uint256 endPrice,
        uint256 duration
    ) external returns (uint256) {
        if(tokenAmount == 0) revert AMOUNT_MUST_BE_HIGHER_THAN_ZERO();
        if(startPrice <= endPrice) revert AMOUNT_MUST_BE_HIGHER_THAN_END_AMOUNT();
        if(duration == 0) revert PERIOD_MUST_BE_HIGHER_THAN_ZERO();
        if(tokenAddress == address(0)) revert INVALID_ADDRESS();

        IERC20 token = IERC20(tokenAddress);
        
        if(token.allowance(msg.sender, address(this)) < tokenAmount) revert INSUFFICIENT_ALLOWANCE();

        if(!token.transferFrom(msg.sender, address(this), tokenAmount)) revert TRANSFER_FAILED();

        uint256 auctionId = auctions.length;
        auctions.push(
            Auction({
                seller: msg.sender,
                tokenAddress: tokenAddress,
                tokenAmount: tokenAmount,
                startPrice: startPrice,
                endPrice: endPrice,
                startTime: block.timestamp,
                duration: duration,
                active: true,
                finalized: false
            })
        );

        emit AuctionCreated(
            auctionId,
            msg.sender,
            tokenAddress,
            tokenAmount,
            startPrice,
            endPrice,
            duration
        );

        return auctionId;
    }

    function getPrice(uint256 auctionId) public view returns (uint256) {
        if(auctionId >= auctions.length) revert INVALID_ID();
        
        Auction storage auction = auctions[auctionId];
        if (!auction.active || block.timestamp >= auction.startTime + auction.duration) {
            return auction.endPrice;
        }

        uint256 elapsed = block.timestamp - auction.startTime;
        uint256 priceDiff = auction.startPrice - auction.endPrice;
        uint256 reduction = (priceDiff * elapsed) / auction.duration;
        return auction.startPrice - reduction;
    }

    function swap(uint256 auctionId) external payable noReentrant {
        if(auctionId >= auctions.length) revert INVALID_ID();
        
        Auction storage auction = auctions[auctionId];
        if(!auction.active) revert INACTIVE_AUCTION();
        if(auction.finalized) revert AUCTION_COMPLETED();
        if(block.timestamp >= auction.startTime + auction.duration) revert AUCTION_HAS_ENDED();
        if(msg.sender == auction.seller) revert CANNOT_BUY_AUCTION_OWNED_BY_YOU();

        uint256 currentPrice = getPrice(auctionId);
        if(msg.value < currentPrice) revert INSUFFICIENT_BALANCE();

        auction.active = false;
        auction.finalized = true;

        IERC20(auction.tokenAddress).transfer(msg.sender, auction.tokenAmount);

        payable(auction.seller).transfer(currentPrice);

        uint256 excess = msg.value - currentPrice;
        if (excess > 0) {
            payable(msg.sender).transfer(excess);
        }

        emit AuctionFinalized(auctionId, msg.sender, currentPrice);
    }

    function cancelAuction(uint256 auctionId) external {
        if(auctionId >= auctions.length) revert INVALID_ID();
        
        Auction storage auction = auctions[auctionId];
        if(msg.sender != auction.seller) revert ONLY_SELLER_CANCEL();
        if(!auction.active) revert INACTIVE_AUCTION();
        if(auction.finalized) revert AUCTION_FINALIZED();

        auction.active = false;
        auction.finalized = true;

        IERC20(auction.tokenAddress).transfer(auction.seller, auction.tokenAmount);
        
        emit AuctionCancelled(auctionId, msg.sender);
    }

    function getAuctionCount() external view returns (uint256) {
        return auctions.length;
    }
}
