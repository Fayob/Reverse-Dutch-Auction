// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

    event AuctionCreated(
        uint256 indexed auctionId,
        address seller,
        address tokenAddress,
        uint256 tokenAmount,
        uint256 startPrice,
        uint256 endPrice,
        uint256 duration
    );

    event AuctionFinalized(
        uint256 indexed auctionId,
        address buyer,
        uint256 price
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
        require(tokenAmount > 0, "Token amount must be greater than 0");
        require(startPrice > endPrice, "Start price must be greater than end price");
        require(duration > 0, "Duration must be greater than 0");
        require(tokenAddress != address(0), "Invalid token address");

        IERC20 token = IERC20(tokenAddress);
        
        // Check allowance before transfer
        require(
            token.allowance(msg.sender, address(this)) >= tokenAmount,
            "Insufficient token allowance"
        );

        // Transfer tokens to contract
        require(
            token.transferFrom(msg.sender, address(this), tokenAmount),
            "Token transfer failed"
        );

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

    function getCurrentPrice(uint256 auctionId) public view returns (uint256) {
        require(auctionId < auctions.length, "Invalid auction ID");
        
        Auction storage auction = auctions[auctionId];
        if (!auction.active || block.timestamp >= auction.startTime + auction.duration) {
            return auction.endPrice;
        }

        uint256 elapsed = block.timestamp - auction.startTime;
        uint256 priceDiff = auction.startPrice - auction.endPrice;
        uint256 reduction = (priceDiff * elapsed) / auction.duration;
        return auction.startPrice - reduction;
    }

    function executeSwap(uint256 auctionId) external payable noReentrant {
        require(auctionId < auctions.length, "Invalid auction ID");
        
        Auction storage auction = auctions[auctionId];
        require(auction.active, "Auction is not active");
        require(!auction.finalized, "Auction already finalized");
        require(
            block.timestamp < auction.startTime + auction.duration,
            "Auction has ended"
        );
        require(msg.sender != auction.seller, "Seller cannot buy their own auction");

        uint256 currentPrice = getCurrentPrice(auctionId);
        require(msg.value >= currentPrice, "Insufficient payment");

        auction.active = false;
        auction.finalized = true;

        // Transfer tokens to buyer
        IERC20(auction.tokenAddress).transfer(msg.sender, auction.tokenAmount);

        // Transfer ETH to seller
        payable(auction.seller).transfer(currentPrice);

        // Refund excess payment if any
        uint256 excess = msg.value - currentPrice;
        if (excess > 0) {
            payable(msg.sender).transfer(excess);
        }

        emit AuctionFinalized(auctionId, msg.sender, currentPrice);
    }

    function cancelAuction(uint256 auctionId) external {
        require(auctionId < auctions.length, "Invalid auction ID");
        
        Auction storage auction = auctions[auctionId];
        require(msg.sender == auction.seller, "Only seller can cancel");
        require(auction.active, "Auction not active");
        require(!auction.finalized, "Auction already finalized");

        auction.active = false;
        auction.finalized = true;

        // Return tokens to seller
        IERC20(auction.tokenAddress).transfer(auction.seller, auction.tokenAmount);
        
        emit AuctionCancelled(auctionId, msg.sender);
    }

    function getAuctionCount() external view returns (uint256) {
        return auctions.length;
    }
}