// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "suave-std/suavelib/Suave.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {FBAHeap} from "../src/FBAHeap.sol";

contract FBA {
    bool ISBUY = true;
    bool ISSELL = false;
    uint256 SAMEPRICEMAXORDS = 1000;

    address[] addressList;

    // Need to maintain separate heaps for bids and asks
    Suave.DataId public askArrayRef;
    Suave.DataId public askMapRef;
    Suave.DataId public bidArrayRef;
    Suave.DataId public bidMapRef;

    // Simplifies placeOrder logic, will not actually be used for publicly storing fills!
    Fill[] public fills;

    // Simplifies cancelOrder logic, will not actually be used for publicly storing fills!
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

    function displayFills(Fill[] memory _fills) public payable {
        for (uint256 i = 0; i < _fills.length; i++) {
            console.log(_fills[i].amount, _fills[i].price);
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

    function getPriceOrdersWithStats(FBAHeap.Order[] memory ords, uint256 price)
        internal
        view
        returns (FBAHeap.Order[] memory orders, uint256 nOrds, uint256 totalAmount)
    {
        orders = new FBAHeap.Order[](SAMEPRICEMAXORDS);
        for (uint256 j = 0; j < ords.length && nOrds < SAMEPRICEMAXORDS; j++) {
            if (ords[j].price == price) {
                orders[nOrds] = ords[j];
                totalAmount += ords[j].amount;
                nOrds++;
            }
        }
    }

    function executeFills() external returns (bytes memory) {
        FBAHeap.ArrayMetadata memory bidAm = FBAHeap.arrGetMetadata(bidArrayRef);
        FBAHeap.MapMetadata memory bidMm = FBAHeap.mapGetMetadata(bidMapRef);
        FBAHeap.ArrayMetadata memory askAm = FBAHeap.arrGetMetadata(askArrayRef);
        FBAHeap.MapMetadata memory askMm = FBAHeap.mapGetMetadata(askMapRef);

        //////////// First part: prioritize the cancel orders
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

        //////////// Second part: match orders with the same price
        FBAHeap.Order memory bestBid = FBAHeap.getTopOrder(bidAm, ISBUY);
        // asks and bids are the orders that will be possibly matched
        FBAHeap.Order[] memory asks = FBAHeap.getTopOrderList(bestBid.price, ISSELL, askAm);
        if (asks.length == 0) {
            return abi.encodeWithSelector(this.executeFillsCallback.selector, fills);
        }

        FBAHeap.Order[] memory bids = FBAHeap.getTopOrderList(asks[0].price, ISBUY, bidAm);
        if (bids.length == 0) {
            return abi.encodeWithSelector(this.executeFillsCallback.selector, fills);
        }

        uint256 previousPrice = 0;
        FBAHeap.Order[] memory bids_;
        FBAHeap.Order[] memory asks_;
        uint256 nBids;
        uint256 nAsks;
        uint256 bidTotalAmount;
        uint256 askTotalAmount;
        uint256 fillRatio;
        for (uint256 i = 0; i < asks.length; i++) {
            uint256 price = asks[i].price;

            // if the price is the same as the previous price, skip the matching because it is already done
            if (previousPrice == price) {
                continue;
            }

            // get orders with the same price
            (bids_, nBids, bidTotalAmount) = getPriceOrdersWithStats(bids, price);
            (asks_, nAsks, askTotalAmount) = getPriceOrdersWithStats(asks, price);

            // match orders with the same price
            if (bidTotalAmount > askTotalAmount) {
                // ask side is fully filled
                // ask side that has less amount
                for (uint256 j = 0; j < nAsks; j++) {
                    FBAHeap.deleteOrder(asks_[j].orderId, ISSELL, askAm, askMm);
                }
                // bid side that has more amount
                fillRatio = askTotalAmount / bidTotalAmount;
                for (uint256 j = 0; j < nBids; j++) {
                    FBAHeap.Order memory order = bids_[j];
                    order.amount -= fillRatio * order.amount;
                    FBAHeap.updateOrder(order, bidAm, bidMm);
                }
                fills.push(Fill(price, askTotalAmount));
            } else if (bidTotalAmount < askTotalAmount) {
                // bid side is fully filled
                // bid side that has less amount
                for (uint256 j = 0; j < nBids; j++) {
                    FBAHeap.deleteOrder(bids_[j].orderId, ISBUY, bidAm, bidMm);
                }
                // ask side that has more amount
                fillRatio = bidTotalAmount / askTotalAmount;
                for (uint256 j = 0; j < nAsks; j++) {
                    FBAHeap.Order memory order = asks_[j];
                    order.amount -= fillRatio * order.amount;
                    FBAHeap.updateOrder(order, askAm, askMm);
                }
                fills.push(Fill(price, bidTotalAmount));
            } else {
                // both sides are fully filled
                for (uint256 j = 0; j < nAsks; j++) {
                    FBAHeap.deleteOrder(asks_[j].orderId, ISSELL, askAm, askMm);
                }
                for (uint256 j = 0; j < nBids; j++) {
                    FBAHeap.deleteOrder(bids_[j].orderId, ISBUY, bidAm, bidMm);
                }
                fills.push(Fill(price, askTotalAmount));
            }

            previousPrice = price;
        }

        //////////// Third part: match orders with different prices
        // take bids and asks again
        bestBid = FBAHeap.getTopOrder(bidAm, ISBUY);
        asks = FBAHeap.getTopOrderList(bestBid.price, ISSELL, askAm);
        if (asks.length == 0) {
            return abi.encodeWithSelector(this.executeFillsCallback.selector, fills);
        }
        bids = FBAHeap.getTopOrderList(asks[0].price, ISBUY, bidAm);
        if (bids.length == 0) {
            return abi.encodeWithSelector(this.executeFillsCallback.selector, fills);
        }

        // get average price in bids and asks
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
        averagePrice /= numNonZero;

        // get total amount in bids
        bidTotalAmount = 0;
        for (uint256 i = 0; i < bids.length; i++) {
            bidTotalAmount += bids[i].amount;
        }
        // get total amount in asks
        askTotalAmount = 0;
        for (uint256 i = 0; i < asks.length; i++) {
            askTotalAmount += asks[i].amount;
        }

        // match orders with different prices
        if (bidTotalAmount > askTotalAmount) {
            // ask side is fully filled
            // ask side that has less amount
            for (uint256 i = 0; i < asks.length; i++) {
                FBAHeap.deleteOrder(asks[i].orderId, ISSELL, askAm, askMm);
            }
            // bid side that has more amount
            fillRatio = askTotalAmount / bidTotalAmount;
            for (uint256 i = 0; i < bids.length; i++) {
                FBAHeap.Order memory order = bids[i];
                order.amount -= fillRatio * order.amount;
                FBAHeap.updateOrder(order, bidAm, bidMm);
            }
            fills.push(Fill(averagePrice, askTotalAmount));
        } else if (bidTotalAmount < askTotalAmount) {
            // bid side is fully filled
            // bid side that has less amount
            for (uint256 i = 0; i < bids.length; i++) {
                FBAHeap.deleteOrder(bids[i].orderId, ISBUY, bidAm, bidMm);
            }
            // ask side that has more amount
            fillRatio = bidTotalAmount / askTotalAmount;
            for (uint256 i = 0; i < asks.length; i++) {
                FBAHeap.Order memory order = asks[i];
                order.amount -= fillRatio * order.amount;
                FBAHeap.updateOrder(order, askAm, askMm);
            }
            fills.push(Fill(averagePrice, bidTotalAmount));
        } else {
            // both sides are fully filled
            for (uint256 i = 0; i < asks.length; i++) {
                FBAHeap.deleteAtIndex(i, ISSELL, askAm, askMm);
            }
            for (uint256 i = 0; i < bids.length; i++) {
                FBAHeap.deleteAtIndex(i, ISBUY, bidAm, bidMm);
            }
            fills.push(Fill(averagePrice, askTotalAmount));
        }

        return abi.encodeWithSelector(this.executeFillsCallback.selector, fills);
    }

    function executeFillsCallback(Fill[] memory _fills) public payable {
        displayFills(_fills);
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
}
