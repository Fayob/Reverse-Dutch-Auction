// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

error INSUFFICIENT_BALANCE();
error AUCTION_ENDED();
error TRANSFER_FAILED();
error AUCTION_START();
error ONLY_SELLER_CAN_START();


contract ReverseDutchAuctionSwap {
    address public seller;
    IERC20 public token;
    uint256 public initialPrice;
    uint256 public priceDecayPerSecond;
    uint256 public startTime;
    uint256 public duration;
    uint256 public tokensForSale;
    bool public auctionEnded;
    address public buyer;

    event AuctionStarted(uint256 initialPrice, uint256 duration);
    event TokensPurchased(address indexed buyer, uint256 price);

    constructor(address _token, uint256 _initialPrice, uint256 _priceDecayPerSecond, uint256 _duration, uint256 _tokensForSale) {
      seller = msg.sender;
      token = IERC20(_token);
      initialPrice = _initialPrice;
      priceDecayPerSecond = _priceDecayPerSecond;
      duration = _duration;
      tokensForSale = _tokensForSale;
    }

    function startAuction() external {
        if(msg.sender != seller) revert ONLY_SELLER_CAN_START();
        if(startTime != 0) revert AUCTION_START();
        if(!token.transferFrom(seller, address(this), tokensForSale)) revert TRANSFER_FAILED();
        startTime = block.timestamp;
        emit AuctionStarted(initialPrice, duration);
    }

    function getCurrentPrice() public view returns (uint256) {
        if (startTime == 0) return initialPrice;
        uint256 timeElapsed = block.timestamp - startTime;
        uint256 discount = timeElapsed * priceDecayPerSecond;
        return discount >= initialPrice ? 0 : initialPrice - discount;
    }

    function buyTokens(uint256 amount) external {
        if(auctionEnded) revert AUCTION_ENDED();
        // if(startTime > 0) revert();, "Auction not started");

        uint256 currentPrice = getCurrentPrice();
        uint256 cost = currentPrice * amount / tokensForSale;
        if(token.balanceOf(msg.sender) < cost) revert INSUFFICIENT_BALANCE();

        auctionEnded = true;
        buyer = msg.sender;
        token.transfer(msg.sender, tokensForSale);
        token.transferFrom(msg.sender, seller, cost);
        
        emit TokensPurchased(msg.sender, cost);
    }
}
