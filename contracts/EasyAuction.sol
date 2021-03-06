// SPDX-License-Identifier: LGPL-3.0-or-newer
pragma solidity >=0.6.8;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./libraries/IterableOrderedOrderSet.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./libraries/IdToAddressBiMap.sol";
import "@openzeppelin/contracts/utils/SafeCast.sol";

contract EasyAuction {
    using SafeMath for uint64;
    using SafeMath for uint96;
    using SafeMath for uint256;
    using SafeCast for uint256; // Todo actually use safecast
    using IterableOrderedOrderSet for IterableOrderedOrderSet.Data;
    using IterableOrderedOrderSet for bytes32;
    using IdToAddressBiMap for IdToAddressBiMap.Data;

    modifier atStageOrderPlacement(uint256 auctionId) {
        require(
            block.timestamp < auctionData[auctionId].auctionEndDate,
            "no longer in order placement phase"
        );
        _;
    }

    modifier atStageSolutionSubmission(uint256 auctionId) {
        require(
            block.timestamp > auctionData[auctionId].auctionEndDate &&
                auctionData[auctionId].clearingPriceOrder == bytes32(0),
            "Auction not in solution submission phase"
        );
        _;
    }

    modifier atStageFinished(uint256 auctionId) {
        require(
            auctionData[auctionId].clearingPriceOrder != bytes32(0),
            "Auction not yet finished"
        );
        _;
    }

    event NewSellOrder(
        uint256 indexed auctionId,
        uint64 indexed userId,
        uint96 buyAmount,
        uint96 sellAmount
    );
    event CancellationSellOrder(
        uint256 indexed auctionId,
        uint64 indexed userId,
        uint96 sellAmount,
        uint96 buyAmount
    );
    event ClaimedFromOrder(
        uint256 indexed auctionId,
        uint64 indexed userId,
        uint96 buyAmount,
        uint96 sellAmount
    );
    event NewAuction(
        uint256 indexed auctionId,
        ERC20 indexed _sellToken,
        ERC20 indexed _buyToken
    );
    event AuctionCleared(
        uint256 indexed auctionId,
        uint96 priceNumerator,
        uint96 priceDenominator
    );
    event UserRegistration(address indexed user, uint64 userId);

    struct AuctionData {
        ERC20 sellToken;
        ERC20 buyToken;
        uint256 auctionEndDate;
        bytes32 initialAuctionOrder;
        uint256 minimumParticipationSellAmount;
        uint256 interimSellAmountSum;
        bytes32 interimOrder;
        bytes32 clearingPriceOrder;
        uint96 volumeClearingPriceOrder;
    }
    mapping(uint256 => IterableOrderedOrderSet.Data) public sellOrders;
    mapping(uint256 => AuctionData) public auctionData;
    IdToAddressBiMap.Data private registeredUsers;
    uint64 public numUsers;
    uint256 public auctionCounter;

    function initiateAuction(
        ERC20 _sellToken,
        ERC20 _buyToken,
        uint256 duration,
        uint96 _sellAmount,
        uint96 _minBuyAmount,
        uint256 minimumParticipationSellAmount
    ) public returns (uint256) {
        uint64 userId = getUserId(msg.sender);
        require(
            _sellToken.transferFrom(msg.sender, address(this), _sellAmount),
            "transfer was not successful"
        );
        require(
            minimumParticipationSellAmount > 0,
            "minimumParticipationSellAmount is not allowed to be zero"
        );
        auctionCounter++;
        auctionData[auctionCounter] = AuctionData(
            _sellToken,
            _buyToken,
            block.timestamp + duration,
            IterableOrderedOrderSet.encodeOrder(
                userId,
                _minBuyAmount,
                _sellAmount
            ),
            minimumParticipationSellAmount,
            0,
            bytes32(0),
            bytes32(0),
            0
        );
        emit NewAuction(auctionCounter, _sellToken, _buyToken);
        return auctionCounter;
    }

    function placeSellOrders(
        uint256 auctionId,
        uint96[] memory _minBuyAmounts,
        uint96[] memory _sellAmounts,
        bytes32[] memory _prevSellOrders
    ) public atStageOrderPlacement(auctionId) {
        (
            ,
            uint96 buyAmountOfInitialAuctionOrder,
            uint96 sellAmountOfInitialAuctionOrder
        ) = auctionData[auctionId].initialAuctionOrder.decodeOrder();
        uint256 sumOfSellAmounts = 0;
        uint64 userId = getUserId(msg.sender);
        for (uint256 i = 0; i < _minBuyAmounts.length; i++) {
            require(
                _minBuyAmounts[i].mul(buyAmountOfInitialAuctionOrder) <
                    sellAmountOfInitialAuctionOrder.mul(_sellAmounts[i]),
                "limit price not better than mimimal offer"
            );
            // orders size should have a minimum size, in order
            // to limit price calculation gas consumption
            require(
                _minBuyAmounts[i] >
                    auctionData[auctionId].minimumParticipationSellAmount,
                "order too small"
            );
            bool success =
                sellOrders[auctionId].insert(
                    IterableOrderedOrderSet.encodeOrder(
                        userId,
                        _minBuyAmounts[i],
                        _sellAmounts[i]
                    ),
                    _prevSellOrders[i]
                );
            if (success) {
                sumOfSellAmounts = sumOfSellAmounts.add(_sellAmounts[i]);
                emit NewSellOrder(
                    auctionId,
                    userId,
                    _minBuyAmounts[i],
                    _sellAmounts[i]
                );
            }
        }
        require(
            auctionData[auctionId].buyToken.transferFrom(
                msg.sender,
                address(this),
                sumOfSellAmounts
            ),
            "transfer was not successful"
        );
    }

    function cancelSellOrders(
        uint256 auctionId,
        bytes32[] memory _sellOrders,
        bytes32[] memory _prevSellOrders
    ) public atStageOrderPlacement(auctionId) {
        uint64 userId = getUserId(msg.sender);
        uint256 claimableAmount = 0;
        for (uint256 i = 0; i < _sellOrders.length; i++) {
            (
                uint64 userIdOfIter,
                uint96 buyAmountOfIter,
                uint96 sellAmountOfIter
            ) = _sellOrders[i].decodeOrder();
            require(
                userIdOfIter == userId,
                "Only the user can cancel his orders"
            );
            if (
                sellOrders[auctionId].remove(_sellOrders[i], _prevSellOrders[i])
            ) {
                claimableAmount = claimableAmount.add(sellAmountOfIter);
                emit CancellationSellOrder(
                    auctionId,
                    userId,
                    buyAmountOfIter,
                    sellAmountOfIter
                );
            }
        }
        require(
            auctionData[auctionId].buyToken.transfer(
                msg.sender,
                claimableAmount
            ),
            "transfer was not successful"
        );
    }

    function precalculateSellAmountSum(
        uint256 auctionId,
        uint256 iterationSteps
    ) public atStageSolutionSubmission(auctionId) {
        (, , uint96 sellAmount) =
            auctionData[auctionId].initialAuctionOrder.decodeOrder();

        // Calculate the bought volume of auctioneer's sell volume
        uint256 sumSellAmount = auctionData[auctionId].interimSellAmountSum;
        bytes32 iterOrder = auctionData[auctionId].interimOrder;
        if (iterOrder == bytes32(0)) {
            iterOrder = IterableOrderedOrderSet.QUEUE_START;
        }

        for (uint256 i = 0; i < iterationSteps; i++) {
            iterOrder = sellOrders[auctionId].next(iterOrder);
            (, , uint96 sellAmountOfIter) = iterOrder.decodeOrder();
            sumSellAmount = sumSellAmount.add(sellAmountOfIter);
        }

        // it is checked that not too many iteration steps were taken:
        // require that the sum of SellAmounts times the price of the last order
        // is not more than intially sold amount
        (, uint96 buyAmountOfIter, uint96 sellAmountOfIter) =
            iterOrder.decodeOrder();
        require(
            sumSellAmount.mul(buyAmountOfIter) <
                sellAmount.mul(sellAmountOfIter),
            "too many orders summed up"
        );

        auctionData[auctionId].interimSellAmountSum = sumSellAmount;
        auctionData[auctionId].interimOrder = iterOrder;
    }

    function verifyPrice(uint256 auctionId, bytes32 price)
        public
        atStageSolutionSubmission(auctionId)
    {
        (, uint96 priceNumerator, uint96 priceDenominator) =
            price.decodeOrder();
        (uint64 auctioneerId, uint96 buyAmount, uint96 sellAmount) =
            auctionData[auctionId].initialAuctionOrder.decodeOrder();

        require(priceNumerator > 0, "price must be postive");

        // Calculate the bought volume of auctioneer's sell volume
        uint256 sumSellAmount = auctionData[auctionId].interimSellAmountSum;
        bytes32 iterOrder = auctionData[auctionId].interimOrder;
        if (iterOrder == bytes32(0)) {
            iterOrder = IterableOrderedOrderSet.QUEUE_START;
        }
        if (sellOrders[auctionId].size > 0) {
            iterOrder = sellOrders[auctionId].next(iterOrder);
            while (iterOrder != price && iterOrder.smallerThan(price)) {
                (, , uint96 sellAmountOfIter) = iterOrder.decodeOrder();
                sumSellAmount = sumSellAmount.add(sellAmountOfIter);
                iterOrder = sellOrders[auctionId].next(iterOrder);
            }
        }
        uint256 sumBuyAmount =
            sumSellAmount.mul(priceNumerator).div(priceDenominator);
        if (price == iterOrder) {
            // case 1: one sellOrder is partically filled
            // The partially filled order is the correct one, if:
            // 1) The sum of buyAmounts is not bigger than the intitial order sell amount
            // i.e, sellAmount >= sumBuyAmount
            // 2) The volume of the particial order is not bigger than its sell volume
            // i.e. auctionData[auctionId].volumeClearingPriceOrder <= sellAmountOfIter,
            (, , uint96 sellAmountOfIter) = iterOrder.decodeOrder();
            uint256 clearingOrderBuyAmount = sellAmount.sub(sumBuyAmount);
            auctionData[auctionId].volumeClearingPriceOrder = uint96(
                clearingOrderBuyAmount.mul(priceDenominator).div(priceNumerator)
            );
            require(
                auctionData[auctionId].volumeClearingPriceOrder <=
                    sellAmountOfIter,
                "order can not be clearing order"
            );
            auctionData[auctionId].clearingPriceOrder = iterOrder;
        } else {
            if (sumBuyAmount < sellAmount) {
                // case 2: initialAuction order is partically filled
                // We require that the price was the initialOrderLimit price's inverse
                // as this ensures that the for-loop iterated through all orders
                // and all orders are considered
                require(
                    priceNumerator.mul(buyAmount) ==
                        sellAmount.mul(priceDenominator),
                    "supplied price must be inverse initialOrderLimit"
                );
                auctionData[auctionId].volumeClearingPriceOrder = uint96(
                    sumBuyAmount
                );
                auctionData[auctionId]
                    .clearingPriceOrder = IterableOrderedOrderSet.encodeOrder(
                    auctioneerId,
                    priceNumerator,
                    priceDenominator
                );
            } else {
                // case 3: no order is partically filled
                // In this case the sumBuyAmount must be equal to
                // the sellAmount of the initialAuctionOrder, without
                // any rounding errors.
                // This price is always existing as we can choose
                // priceNumerator = sellAmount and priceDenominator = sumSellAmount
                auctionData[auctionId].clearingPriceOrder = price;
                require(
                    sumBuyAmount == sellAmount,
                    "price is not clearing price"
                );
                require(
                    priceNumerator.mul(buyAmount) <=
                        sellAmount.mul(priceDenominator),
                    "clearing price is better than initialAuctionOrder"
                );
            }
        }

        emit AuctionCleared(auctionId, priceNumerator, priceDenominator);
        claimAuctioneerFunds(auctionId);
    }

    function claimFromParticipantOrder(
        uint256 auctionId,
        bytes32[] memory orders,
        bytes32[] memory previousOrders
    )
        public
        atStageFinished(auctionId)
        returns (uint256 sumSellTokenAmount, uint256 sumBuyTokenAmount)
    {
        AuctionData memory auction = auctionData[auctionId];
        (, uint96 priceNumerator, uint96 priceDenominator) =
            auction.clearingPriceOrder.decodeOrder();
        (uint64 userId, , ) = orders[0].decodeOrder();
        for (uint256 i = 0; i < orders.length; i++) {
            require(
                sellOrders[auctionId].remove(orders[i], previousOrders[i]),
                "order is no longer claimable"
            );
            (uint64 userIdOrder, uint96 buyAmount, uint96 sellAmount) =
                orders[i].decodeOrder();
            require(
                userIdOrder == userId,
                "only allowed to claim for same user"
            );
            if (orders[i] == auction.clearingPriceOrder) {
                sumSellTokenAmount = sumSellTokenAmount.add(
                    auction.volumeClearingPriceOrder.mul(priceNumerator).div(
                        priceDenominator
                    )
                );
                sumBuyTokenAmount = sumBuyTokenAmount.add(
                    sellAmount.sub(auction.volumeClearingPriceOrder)
                );
            } else {
                if (orders[i].smallerThan(auction.clearingPriceOrder)) {
                    sumSellTokenAmount = sumSellTokenAmount.add(
                        sellAmount.mul(priceNumerator).div(priceDenominator)
                    );
                } else {
                    sumBuyTokenAmount = sumBuyTokenAmount.add(sellAmount);
                }
            }
            emit ClaimedFromOrder(auctionId, userId, buyAmount, sellAmount);
        }
        sendOutTokens(auctionId, sumSellTokenAmount, sumBuyTokenAmount, userId);
    }

    function claimAuctioneerFunds(uint256 auctionId)
        internal
        returns (uint256 sellTokenAmount, uint256 buyTokenAmount)
    {
        (uint64 auctioneerId, uint96 buyAmount, uint96 sellAmount) =
            auctionData[auctionId].initialAuctionOrder.decodeOrder();
        auctionData[auctionId].initialAuctionOrder = bytes32(0);
        (, uint96 priceNumerator, uint96 priceDenominator) =
            auctionData[auctionId].clearingPriceOrder.decodeOrder();
        if (priceNumerator.mul(buyAmount) == priceDenominator.mul(sellAmount)) {
            // In this case we have a partial match of the initialSellOrder
            sellTokenAmount = sellAmount.sub(
                auctionData[auctionId].volumeClearingPriceOrder
            );
            buyTokenAmount = auctionData[auctionId]
                .volumeClearingPriceOrder
                .mul(priceDenominator)
                .div(priceNumerator);
        } else {
            buyTokenAmount = sellAmount.mul(priceDenominator).div(
                priceNumerator
            );
        }
        sendOutTokens(auctionId, sellTokenAmount, buyTokenAmount, auctioneerId);
    }

    function sendOutTokens(
        uint256 auctionId,
        uint256 sellTokenAmount,
        uint256 buyTokenAmount,
        uint64 userId
    ) internal {
        address userAddress = registeredUsers.getAddressAt(userId);
        require(
            auctionData[auctionId].sellToken.transfer(
                userAddress,
                sellTokenAmount
            ),
            "Claim transfer for sellToken failed"
        );
        require(
            auctionData[auctionId].buyToken.transfer(
                userAddress,
                buyTokenAmount
            ),
            "Claim transfer for buyToken failed"
        );
    }

    function registerUser(address user) public returns (uint64 userId) {
        require(
            registeredUsers.insert(numUsers, user),
            "User already registered"
        );
        userId = numUsers;
        numUsers = numUsers.add(1).toUint64();
        emit UserRegistration(user, userId);
    }

    function getUserId(address user) public returns (uint64 userId) {
        if (registeredUsers.hasAddress(user)) {
            return registeredUsers.getId(user);
        } else {
            return registerUser(user);
        }
    }

    function getSecondsRemainingInBatch(uint256 auctionId)
        public
        view
        returns (uint256)
    {
        if (auctionData[auctionId].auctionEndDate < block.timestamp) {
            return 0;
        }
        return auctionData[auctionId].auctionEndDate.sub(block.timestamp);
    }

    function containsOrder(uint256 auctionId, bytes32 order)
        public
        view
        returns (bool)
    {
        return sellOrders[auctionId].contains(order);
    }
}
