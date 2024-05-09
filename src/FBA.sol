// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "suave-std/suavelib/Suave.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {FBAHeap} from "../src/FBAHeap.sol";

contract FBA {
    bool ISBUY = true;
    bool ISSELL = false;

    address[] addressList;

    // Need to maintain separate heaps for bids and asks
    Suave.DataId public askArrayRef;
    Suave.DataId public askMapRef;
    Suave.DataId public bidArrayRef;
    Suave.DataId public bidMapRef;

    Fill[] public fills;
    Cancel[] public cancels;

    struct Fill {
        uint256 price;
        uint256 amount;
    }

    struct Cancel {
        string orderId;
        bool side;
    }

    struct PlaceResult {
        uint256 price;
        bool side;
        uint256 amount;
    }

    struct CancelResult {
        string orderId;
        bool side;
    }

    event FillEvent(Fill);
    event OrderPlace(uint256 price, uint256 amount, bool side);
    event OrderCancel(string orderId, bool side);

    constructor() {
        addressList = new address[](1);
        // from Suave.sol: address public constant ANYALLOWED = 0xC8df3686b4Afb2BB53e60EAe97EF043FE03Fb829;
        addressList[0] = 0xC8df3686b4Afb2BB53e60EAe97EF043FE03Fb829;
    }

    function initFBA() external returns (bytes memory) {
        // For the bid, array
        Suave.DataRecord memory bidArr = Suave.newDataRecord(0, addressList, addressList, "suaveFBA:v0:dataId");
        FBAHeap.ArrayMetadata memory bidAm = FBAHeap.ArrayMetadata(0, bidArr.id);
        FBAHeap.arrSetMetadata(bidAm);

        // For the ask, array
        Suave.DataRecord memory askArr = Suave.newDataRecord(0, addressList, addressList, "suaveFBA:v0:dataId");
        FBAHeap.ArrayMetadata memory askAm = FBAHeap.ArrayMetadata(0, askArr.id);
        FBAHeap.arrSetMetadata(askAm);

        // For the bid, map
        Suave.DataRecord memory bidMap = Suave.newDataRecord(0, addressList, addressList, "suaveFBA:v0:dataId");
        FBAHeap.MapMetadata memory bidMm = FBAHeap.MapMetadata(bidMap.id);
        FBAHeap.mapSetMetadata(bidMm);

        // For the ask, map
        Suave.DataRecord memory askMap = Suave.newDataRecord(0, addressList, addressList, "suaveFBA:v0:dataId");
        FBAHeap.MapMetadata memory askMm = FBAHeap.MapMetadata(askMap.id);
        FBAHeap.mapSetMetadata(askMm);

        return abi.encodeWithSelector(this.initFBACallback.selector, bidArr.id, bidMap.id, askArr.id, askMap.id);
    }

    /**
     * @notice Displays the fills
     */
    function displayFills(Fill[] memory _fills) public payable {
        for (uint256 i = 0; i < _fills.length; i++) {
            console.log("Fill price:", Strings.toString(_fills[i].price), "amount:", Strings.toString(_fills[i].amount));
            emit FillEvent(_fills[i]);
        }
    }

    /**
     * @notice Allows user to place a new order and immediately checks for fills
     */
    function placeOrder(FBAHeap.Order memory ord) external returns (bytes memory) {
        // Add it to bids or asks heap...
        if (ord.side == ISBUY) {
            FBAHeap.ArrayMetadata memory bidAm = FBAHeap.arrGetMetadata(bidArrayRef);
            FBAHeap.MapMetadata memory bidMm = FBAHeap.mapGetMetadata(bidMapRef);
            FBAHeap.insertOrder(ord, bidAm, bidMm);
        } else if (ord.side == ISSELL) {
            FBAHeap.ArrayMetadata memory askAm = FBAHeap.arrGetMetadata(askArrayRef);
            FBAHeap.MapMetadata memory askMm = FBAHeap.mapGetMetadata(askMapRef);
            FBAHeap.insertOrder(ord, askAm, askMm);
        }

        // Assuming order placement was always successful?
        PlaceResult memory placeResult = PlaceResult(ord.price, ord.side, ord.amount);
        return abi.encodeWithSelector(this.placeOrderCallback.selector, placeResult);
    }

    /**
     * @notice Allows user to cancel an order they previously placed
     */
    function cancelOrder(string memory orderId, bool side) external returns (bytes memory) {
        cancels.push(Cancel(orderId, side));

        CancelResult memory cancelResult = CancelResult(orderId, side);
        return abi.encodeWithSelector(this.cancelOrderCallback.selector, cancelResult);
    }

    /**
     * @notice Executes fills for the current state of the order book
     */
    function executeFills() external returns (bytes memory) {
        FBAHeap.ArrayMetadata memory bidAm = FBAHeap.arrGetMetadata(bidArrayRef);
        FBAHeap.MapMetadata memory bidMm = FBAHeap.mapGetMetadata(bidMapRef);
        FBAHeap.ArrayMetadata memory askAm = FBAHeap.arrGetMetadata(askArrayRef);
        FBAHeap.MapMetadata memory askMm = FBAHeap.mapGetMetadata(askMapRef);

        ////// First part: prioritize the cancel orders
        for (uint256 i = 0; i < cancels.length; i++) {
            string memory orderId = cancels[i].orderId;
            bool side = cancels[i].side;

            if (side == ISBUY) {
                FBAHeap.deleteOrder(orderId, side, bidAm, bidMm);
            } else if (side == ISSELL) {
                FBAHeap.deleteOrder(orderId, side, askAm, askMm);
            }
        }
        // remove all cancel orders
        cancels = new Cancel[](0);

        ////// Second part: match orders with the same price
        FBAHeap.Order[] memory bids;
        FBAHeap.Order[] memory asks;
        (bids, asks) = getMatchingOrderCandidates(bidAm, askAm);
        if (bids.length == 0 || asks.length == 0) {
            return abi.encodeWithSelector(this.executeFillsCallback.selector, fills);
        }

        uint256 previousPrice = 0;
        FBAHeap.Order[] memory bidsAtPrice;
        FBAHeap.Order[] memory asksAtPrice;
        uint256 bidTotalAmount;
        uint256 askTotalAmount;
        for (uint256 i = 0; i < asks.length; i++) {
            uint256 price = asks[i].price;

            // If the price is the same as the previous price, skip the matching because it is already done
            if (previousPrice == price) {
                continue;
            }

            // Get orders with the same price
            (bidsAtPrice, bidTotalAmount) = getPriceOrdersWithStats(bids, price);
            (asksAtPrice, askTotalAmount) = getPriceOrdersWithStats(asks, price);

            // Match orders with the same price
            executeMatch(bidsAtPrice, asksAtPrice, price, bidTotalAmount, askTotalAmount, bidAm, bidMm, askAm, askMm);

            previousPrice = price;
        }

        ////// Third part: match orders with different prices
        // Get bids and asks again because the previous matching might have changed the order book
        (bids, asks) = getMatchingOrderCandidates(bidAm, askAm);
        if (bids.length == 0 || asks.length == 0) {
            return abi.encodeWithSelector(this.executeFillsCallback.selector, fills);
        }

        // Get stats for matching orders
        uint256 averagePrice = getAveragePrice(bids, asks);
        bidTotalAmount = getTotalAmount(bids);
        askTotalAmount = getTotalAmount(asks);

        // match orders with different prices
        executeMatch(bids, asks, averagePrice, bidTotalAmount, askTotalAmount, bidAm, bidMm, askAm, askMm);

        return abi.encodeWithSelector(this.executeFillsCallback.selector, fills);
    }

    //////////// Internal methods

    /**
     * @notice Returns the list of orders with the same price and the total amount at the price
     */
    function getPriceOrdersWithStats(FBAHeap.Order[] memory ords, uint256 price)
        internal
        pure
        returns (FBAHeap.Order[] memory ordersAtPrice, uint256 totalAmountAtPrice)
    {
        uint256 nOrds = 0;
        for (uint256 j = 0; j < ords.length; j++) {
            if (ords[j].price == price) {
                nOrds++;
            }
        }
        ordersAtPrice = new FBAHeap.Order[](nOrds);
        uint256 nOrdsCount = 0; // The final value of `nOrdsCount` should be equal to `nOrds`
        for (uint256 j = 0; j < ords.length; j++) {
            if (ords[j].price == price) {
                ordersAtPrice[nOrdsCount] = ords[j];
                totalAmountAtPrice += ords[j].amount;
                nOrdsCount++;
            }
        }
    }

    /**
     * @notice Returns the list of orders that can be matched
     */
    function getMatchingOrderCandidates(FBAHeap.ArrayMetadata memory bidAm, FBAHeap.ArrayMetadata memory askAm)
        internal
        returns (FBAHeap.Order[] memory, FBAHeap.Order[] memory)
    {
        FBAHeap.Order[] memory empty = new FBAHeap.Order[](0);

        // If there are no bids or asks at all, return empty tuple
        if (bidAm.length == 0 || askAm.length == 0) {
            return (empty, empty);
        }
        FBAHeap.Order memory greatestBid = FBAHeap.getTopOrder(bidAm, ISBUY);
        FBAHeap.Order[] memory asksLessThanGreatestBid = FBAHeap.getTopOrderList(greatestBid.price, ISSELL, askAm);
        // If there are no asks at all, return empty tuple because there is no match
        if (asksLessThanGreatestBid.length == 0) {
            return (empty, empty);
        }
        FBAHeap.Order[] memory bidsGreaterThanLeastAsk =
            FBAHeap.getTopOrderList(asksLessThanGreatestBid[0].price, ISBUY, bidAm);

        return (bidsGreaterThanLeastAsk, asksLessThanGreatestBid);
    }

    /**
     * @notice Returns the average price of the orders
     */
    function getAveragePrice(FBAHeap.Order[] memory bids, FBAHeap.Order[] memory asks)
        internal
        pure
        returns (uint256)
    {
        uint256 averagePrice = 0;
        uint256 numNonZero = 0;
        for (uint256 i = 0; i < bids.length; i++) {
            if (bids[i].price != 0) {
                averagePrice += bids[i].price;
                numNonZero++;
            }
        }
        for (uint256 i = 0; i < asks.length; i++) {
            if (asks[i].price != 0) {
                averagePrice += asks[i].price;
                numNonZero++;
            }
        }
        return averagePrice / numNonZero;
    }

    /**
     * @notice Returns the total amount of the orders
     */
    function getTotalAmount(FBAHeap.Order[] memory ords) internal pure returns (uint256) {
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < ords.length; i++) {
            totalAmount += ords[i].amount;
        }
        return totalAmount;
    }

    /**
     * @notice Executes the match between the orders
     */
    function executeMatch(
        FBAHeap.Order[] memory bidOrds,
        FBAHeap.Order[] memory askOrds,
        uint256 price,
        uint256 bidTotalAmount,
        uint256 askTotalAmount,
        FBAHeap.ArrayMetadata memory bidAm,
        FBAHeap.MapMetadata memory bidMm,
        FBAHeap.ArrayMetadata memory askAm,
        FBAHeap.MapMetadata memory askMm
    ) internal {
        if (bidTotalAmount == 0 || askTotalAmount == 0) {
            // If either side is empty, return
            return;
        } else if (bidTotalAmount > askTotalAmount) {
            // Ask side is fully filled
            deleteMatchedOrders(askOrds, askAm, askMm);
            updateMatchedOrders(bidOrds, bidTotalAmount, askTotalAmount, bidAm, bidMm);
            fills.push(Fill(price, askTotalAmount));
        } else if (bidTotalAmount < askTotalAmount) {
            // Bid side is fully filled
            deleteMatchedOrders(bidOrds, bidAm, bidMm);
            updateMatchedOrders(askOrds, askTotalAmount, bidTotalAmount, askAm, askMm);
            fills.push(Fill(price, bidTotalAmount));
        } else {
            // Both sides are fully filled
            deleteMatchedOrders(bidOrds, bidAm, bidMm);
            deleteMatchedOrders(askOrds, askAm, askMm);
            fills.push(Fill(price, bidTotalAmount));
        }
    }

    /**
     * @notice Deletes the matched orders
     */
    function deleteMatchedOrders(
        FBAHeap.Order[] memory ords,
        FBAHeap.ArrayMetadata memory am,
        FBAHeap.MapMetadata memory mm
    ) internal {
        for (uint256 i = 0; i < ords.length; i++) {
            FBAHeap.deleteOrder(ords[i].orderId, ords[i].side, am, mm);
        }
    }

    /**
     * @notice Updates the matched orders
     */
    function updateMatchedOrders(
        FBAHeap.Order[] memory ords,
        uint256 greaterTotalAmount,
        uint256 smallerTotalAmount,
        FBAHeap.ArrayMetadata memory am,
        FBAHeap.MapMetadata memory mm
    ) internal {
        uint256 fillRatio = smallerTotalAmount / greaterTotalAmount;
        for (uint256 i = 0; i < ords.length; i++) {
            FBAHeap.Order memory order = ords[i];
            order.amount -= fillRatio * order.amount;
            FBAHeap.updateOrder(order, am, mm);
        }
    }

    //////////// Callback methods

    function initFBACallback(
        Suave.DataId _bidArrayRef,
        Suave.DataId _bidMapRef,
        Suave.DataId _askArrayRef,
        Suave.DataId _askMapRef
    ) public payable {
        askArrayRef = _askArrayRef;
        askMapRef = _askMapRef;
        bidArrayRef = _bidArrayRef;
        bidMapRef = _bidMapRef;
    }

    function placeOrderCallback(PlaceResult memory result) public payable {
        emit OrderPlace(result.price, result.amount, result.side);
    }

    function cancelOrderCallback(CancelResult memory result) public payable {
        emit OrderCancel(result.orderId, result.side);
    }

    function executeFillsCallback(Fill[] memory _fills) public payable {
        displayFills(_fills);
    }
}
