import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";

describe("ReverseDutchAuctionSwap", function () {
  const INITIAL_SUPPLY = ethers.parseEther("1000000");

  const TOKEN_AMOUNT = ethers.parseEther("100");
  const START_PRICE = ethers.parseEther("1");
  const END_PRICE = ethers.parseEther("0.1");
  const DURATION = 3600;

  async function deployAuction() {

    const [owner, seller, buyer] = await ethers.getSigners();

    const TestToken = await ethers.getContractFactory("Token");
    const testToken = await TestToken.deploy(INITIAL_SUPPLY);

    const ReverseDutchAuctionSwap = await ethers.getContractFactory("ReverseDutchAuctionSwap");
    const auction = await ReverseDutchAuctionSwap.deploy();


    await testToken.transfer(seller.address, TOKEN_AMOUNT);
    await testToken.connect(seller).approve(auction.target, TOKEN_AMOUNT);

    return { testToken, auction, owner, seller, buyer };
  }

  describe("Auction Creation", function () {
    it("Should create an auction with correct parameters", async function () {
      const { auction, testToken, seller } = await loadFixture(deployAuction);

      await expect(auction.connect(seller).createAuction(
        testToken.target,
        TOKEN_AMOUNT,
        START_PRICE,
        END_PRICE,
        DURATION
      )).to.emit(auction, "AuctionCreated");

      const auctionData = await auction.auctions(0);
      expect(auctionData.seller).to.equal(seller.address);
      expect(auctionData.tokenAmount).to.equal(TOKEN_AMOUNT);
      expect(auctionData.startPrice).to.equal(START_PRICE);
      expect(auctionData.endPrice).to.equal(END_PRICE);
    });

    it("Should fail if token amount is 0", async function () {
      const { auction, testToken, seller } = await loadFixture(deployAuction);

      await expect(auction.connect(seller).createAuction(
        testToken.target,
        0,
        START_PRICE,
        END_PRICE,
        DURATION
      )).to.be.revertedWithCustomError(auction, "AMOUNT_MUST_BE_HIGHER_THAN_ZERO()");
    });
  });

  describe("Price Mechanism", function () {
    it("Should decrease price correctly over time", async function () {
      const { auction, testToken, seller } = await loadFixture(deployAuction);

      await auction.connect(seller).createAuction(
        testToken.target,
        TOKEN_AMOUNT,
        START_PRICE,
        END_PRICE,
        DURATION
      );

      const initialPrice = await auction.getPrice(0);
      expect(initialPrice).to.be.closeTo(START_PRICE, ethers.parseEther("0.01"));

      await time.increase(DURATION / 2);

      const midPrice = await auction.getPrice(0);
      const expectedMidPrice = START_PRICE - ((START_PRICE - END_PRICE) / BigInt(2));
      expect(midPrice).to.be.closeTo(expectedMidPrice, ethers.parseEther("0.01"));
    });
  });

  describe("Swap", function () {
    it("Should swap successfully", async function () {
      const { auction, testToken, seller, buyer } = await loadFixture(deployAuction);

      await auction.connect(seller).createAuction(
        testToken.target,
        TOKEN_AMOUNT,
        START_PRICE,
        END_PRICE,
        DURATION
      );

      await time.increase(1800);

      const currentPrice = await auction.getPrice(0);

      const initialBuyerBalance = await testToken.balanceOf(buyer.address);
      const initialSellerEthBalance = await ethers.provider.getBalance(seller.address);


      await expect(auction.connect(buyer).swap(0, { value: currentPrice }))
        .to.emit(auction, "AuctionFinalized");

      expect(await testToken.balanceOf(buyer.address))
        .to.equal(initialBuyerBalance + TOKEN_AMOUNT);


      expect(await ethers.provider.getBalance(seller.address))
        .to.be.above(initialSellerEthBalance);
    });

    it("Should prevent multiple purchases for same auction", async function () {
      const { auction, testToken, seller, buyer, owner } = await loadFixture(deployAuction);

      await auction.connect(seller).createAuction(
        testToken.target,
        TOKEN_AMOUNT,
        START_PRICE,
        END_PRICE,
        DURATION
      );

      const currentPrice = await auction.getPrice(0);

      await auction.connect(buyer).swap(0, { value: currentPrice });

      await expect(auction.connect(owner).swap(0, { value: currentPrice }))
        .to.be.revertedWithCustomError(auction, "INACTIVE_AUCTION()");
    });
  });

  describe("Edge Cases", function () {
    it("Should not allow purchase after auction ends", async function () {
      const { auction, testToken, seller, buyer } = await loadFixture(deployAuction);

      await auction.connect(seller).createAuction(
        testToken.target,
        TOKEN_AMOUNT,
        START_PRICE,
        END_PRICE,
        DURATION
      );

      await time.increase(DURATION + 1);

      await expect(auction.connect(buyer).swap(0, { value: END_PRICE }))
        .to.be.revertedWithCustomError(auction, "AUCTION_HAS_ENDED()");
    });

    it("Should allow seller to cancel auction", async function () {
      const { auction, testToken, seller } = await loadFixture(deployAuction);

      await auction.connect(seller).createAuction(
        testToken.target,
        TOKEN_AMOUNT,
        START_PRICE,
        END_PRICE,
        DURATION
      );

      const initialSellerBalance = await testToken.balanceOf(seller.address);
      
      await auction.connect(seller).cancelAuction(0);

      expect(await testToken.balanceOf(seller.address))
        .to.equal(initialSellerBalance + TOKEN_AMOUNT);

      const auctionData = await auction.auctions(0);
      expect(auctionData.active).to.be.false;
      expect(auctionData.finalized).to.be.true;
    });
  });
});