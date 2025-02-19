const { ethers } = require("hardhat");

async function main() {
    const [deployer, seller, buyer] = await ethers.getSigners();

    console.log("Deploying contracts with the account:", deployer.address);

    const Token = await ethers.getContractFactory("ReverseDutchAuctionSwap");
    const token = await Token.deploy();
    await token.waitForDeployment();
    console.log("Token deployed to:", token.target);

    const initialPrice = ethers.parseEther("10");
    const priceDecayPerSecond = ethers.parseEther("0.1");
    const duration = 3600;
    const tokensForSale = ethers.parseUnits("100", 18);

    const Auction = await ethers.getContractFactory("ReverseDutchAuctionSwap");
    const auction = await Auction.deploy(token.target, initialPrice, priceDecayPerSecond, duration, tokensForSale);
    await auction.waitForDeployment();
    console.log("Auction deployed to:", auction.target);

    await token.transfer(seller.address, tokensForSale);
    await token.connect(seller).approve(auction.target, tokensForSale);
    await auction.connect(seller).startAuction();
    console.log("Auction started by seller");

    console.log("Simulating swap...");
    await ethers.provider.send("evm_increaseTime", [1200]);
    await ethers.provider.send("evm_mine");
    
    const currentPrice = await auction.getCurrentPrice();
    console.log("Current price after 1200 seconds:", ethers.formatEther(currentPrice));

    await token.connect(buyer).approve(auction.target, currentPrice);
    await auction.connect(buyer).buyTokens(tokensForSale);
    console.log("Buyer purchased tokens at:", ethers.formatEther(currentPrice));
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
})