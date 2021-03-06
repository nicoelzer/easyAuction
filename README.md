# EasyAuction

EasyAuction should become a platform to execute batch auctions for fair initial offerings and token buyback programs. Batch auctions are a market mechanism for matching limit orders of buyers and sellers of a particular good with one fair clearing price.
Already in traditional finance, batch auctions have established themselves as a tool for initial offerings, and in the blockchain ecosystem, they are expected to become a fundamental DeFi building lego brick for price-discovery as well.
The EasyAuction platform is inspired by the auction mechanism of the Gnosis Protocol v1, which has shown a significant product-market fit for initial dex offerings (IDOs) (cp. sales of DIA, mStable, etc…). EasyAuction improves significantly the user experience for IDOs, by settling up arbitrary many bids with a single clearing price instead of roughly 28 orders and thereby making the mechanism fairer, easier to use, and more predictable.
Given the emerging regulations for IDOs and utility sales - see MiCA -, EasyAuction is intending to comply with them and enabling new projects a safe start without legal risks.

## Use cases

### Initial token offering with a fair price-discovery

This batch auction mechanism allows communities, projects, and DAOs to offer their future stakeholders fair participation within their ecosystem by acquiring utility and governance tokens. One of the promises of DeFi is the democratization and communitization of big corporate infrastructures to build open platforms for the public good. By running a batch auction, these projects facilitate one of the fairest distribution of stakes. Projects should demonstrate their interest in fair participation by setting a precedence for future processes by choosing this fair auction principle over private multi-stage sales.
Auction based initial offerings are also picking up in the traditional finance world. Google was one of the first big tech companies using a similar auction mechanism with a unique clearing price to IPO. Nowadays, companies like Slack and Spotify are advocating similar approaches as well via Direct Listings: Selling their stocks in the pre-open auction on the first day of trading.
Overall this market for initial token offerings is expected to grow significantly over time together with the ecosystem. Even on gnosis protocol version 1, a platform not intended for this use case, was able to facilitate IDOs with a total of more than 20 million funding.

### Token buy back programs

Many decentralized projects have to buy back their tokens or auction off their tokens to clear deficits within their protocol. This EasyAuction platform allows them to schedule individual auctions to facilitate these kinds of operations.

### Initial credit offering

First implementations of [yTokens are live](https://defirate.com/uma-ycomp-shorts/) on the ethereum blockchain. The initial price finding and matching of creditor and debtor for such credit instruments can be done in a very fair manner for these kind of financial contracts.

## Protocol description

### The batch auction mechanism

In this auction type a pre-defined amount of tokens is auctioned off. Anyone can bid to buy these tokens by placing a buy-order with a specified limit price during the whole bidding time. At the end of the auction, the final price is calculated by the following method: The buy volumes from the highest bids are getting added up until this sum reaches the initial sell volume. The bid increasing the overall buy volume to is the bid defining the uniform clearing price. All bids with higher price will be settled and traded against the initial sell volume with the clearing price. All bids with a lower price will not be considered for the settlement. The principle is described best with the following diagram:
![image from nytimes](./assets/Auction_info_pic.png)

### Specific implementation batch auction

EasyAuction allows anyone to start a new auction of any ERC20 token (sellToken) against another ERC20 token (buyToken). The entity initiating the auction, the auctioneer, has to define the amount of token to be sold, the minimal price for the auction, and the end-time of the auction. Once the auctioneer initiates the auction with a ethereum transaction transferring the sellTokens and setting the parameters. From this moment on, anyone can participate as a buyer and submit bids. Each buyer places buy-orders with a specified limit price into the system. The buy amount of an order must be at least 1/MIN_BUY_AMOUNT_FACTOR of the auctioned sell amount, where x can be set during the auction initialization. Once an order is placed, orders can no longer be canceled and the tokens for the buying process are locked.
Once the auction ends, the final clearing price will be determined via an onchain calculation. Since, there is an minimal buy amount per order no more than MIN_BUY_AMOUNT_FACTOR orders need to be read onchain for the price calculation. Since roughly 2500 orders can be processed within one ethereum transaction, the price can be verified within MIN_BUY_AMOUNT_FACTOR/ 2500 blocks.

Once the price of an auction has been verified onchain, everyone can claim their part of the auction. The auctioneer can withdraw the bought funds, the buyers being matched in the auction can withdraw their bought tokens. The buyers bidding with a too low price which were not matched in the auction can withdraw their bidding funds back.

## Comparison to Dutch auctions

The proposed batch auction system has a number of advantages over dutch auction.

- The biggest advantage is certainly that buyers don't have to wait for a certain time to submit orders, but that they can submit orders at any time. This makes the system much more convenient for users.
- Dutch auctions have a very high activity right before the auction is closing. If pieces of the infrastructure are not working reliable during this time period, then prices can fall further than expected, causing a loss for the auctioneer. Also, high gas prices during this short time period can be a hindering factor for buyers to quickly join the auction.
- Dutch auctions calculate their price based the blocktime. This pricing is hard to predict for all participants, as the mining is a stochastical process Additionally, the unpredictability for the mining time of the next block
- Dutch auctions are causing a gas price bidding war to close the auction. In contrast in batch auction, different buyers will bid against other bidder in the mem-pool. Especially, once (EIP-1559)[https://eips.ethereum.org/EIPS/eip-1559] is implemented and the mining of a transaction is guaranteed for the next block, then bidders have to compete on bidding limit-prices instead of the gas-prices to get included into the auction.

## Instructions

### Backend

Install dependencies

```
git clone easyAuction
cd easyAuction
yarn
yarn build
```

Running tests:

```
yarn test
```

Run migration:

```
yarn deploy --network $NETWORK
```

Verify on etherscan:

```
npx hardhat verify --network $NETWORK DEPLOYED_CONTRACT_ADDRESS
```

### Running scripts

Initiating a new auction:

```

yarn hardhat run  src/scripts/initiate_new_auction_hardcoded.ts --network $NETWORK
```
