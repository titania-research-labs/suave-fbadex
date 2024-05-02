// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "suave-std/suavelib/Suave.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {FBAHeap} from "../src/FBAHeap.sol";

contract FBA {
    bool ISBUY = true;
    bool ISSELL = false;
    uint256 SAMEPRICEMAXORDS = 10; // TODO: optimize this value

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
        uint256 amount;
        uint256 price;
    }

    struct Cancel {
        string clientId;
        bool side;
    }

    struct PlaceResult {
        uint256 price;
        bool side;
        uint256 amount;
    }

    struct CancelResult {
        string clientId;
        bool side;
    }

    event FillEvent(Fill);
    event OrderPlace(uint256 price, bool side, uint256 amount);
    event OrderCancel(string clientId, bool side);

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
    function placeOrder(FBAHeap.FBAOrder memory ord) external returns (bytes memory) {
        // Add it to bids or asks heap...
        if (ord.side == ISBUY) {
            FBAHeap.ArrayMetadata memory bidAm = FBAHeap.arrGetMetadata(bidArrayRef);
            FBAHeap.MapMetadata memory bidMm = FBAHeap.mapGetMetadata(bidMapRef);
            FBAHeap.insertOrder(bidAm, bidMm, ord);
        } else if (ord.side == ISSELL) {
            FBAHeap.ArrayMetadata memory askAm = FBAHeap.arrGetMetadata(askArrayRef);
            FBAHeap.MapMetadata memory askMm = FBAHeap.mapGetMetadata(askMapRef);
            FBAHeap.insertOrder(askAm, askMm, ord);
        }

        // Assuming order placement was always successful?
        PlaceResult memory placeResult = PlaceResult(ord.price, ord.side, ord.amount);
        return abi.encodeWithSelector(this.placeOrderCallback.selector, placeResult);
    }

    /**
     * @notice Allows user to cancel an order they previously placed
     */
    function cancelOrder(string memory clientId, bool side) external returns (bytes memory) {
        cancels.push(Cancel(clientId, side));

        CancelResult memory cancelResult = CancelResult(clientId, side);
        return abi.encodeWithSelector(this.cancelOrderCallback.selector, cancelResult);
    }

    // TODO: optimize this part by using `break` when there is no more order at the price
    function getOrdersInfoAtPrice(FBAHeap.FBAOrder[] memory ords, uint256 price)
        internal
        view
        returns (uint256[] memory indices, uint256 nOrds, uint256 totalAmount)
    {
        indices = new uint256[](SAMEPRICEMAXORDS);
        for (uint256 j = 0; j < ords.length; j++) {
            if (ords[j].price == price) {
                indices[nOrds] = j;
                totalAmount += ords[j].amount;
                nOrds++;

                if (nOrds == SAMEPRICEMAXORDS) {
                    break;
                }
            }
        }
    }

    function executeFills() external returns (bytes memory) {
        FBAHeap.ArrayMetadata memory bidAm = FBAHeap.arrGetMetadata(bidArrayRef);
        FBAHeap.MapMetadata memory bidMm = FBAHeap.mapGetMetadata(bidMapRef);
        FBAHeap.ArrayMetadata memory askAm = FBAHeap.arrGetMetadata(askArrayRef);
        FBAHeap.MapMetadata memory askMm = FBAHeap.mapGetMetadata(askMapRef);

        uint256 bidFallbackPrice = 0;
        uint256 askFallbackPrice = type(uint256).max;
        FBAHeap.FBAOrder memory bestBid = FBAHeap.peekTopOne(bidAm, bidFallbackPrice, ISBUY);
        // asks and bids are the orders that will be possibly matched
        FBAHeap.FBAOrder[] memory asks = FBAHeap.peekTopList(askAm, bestBid.price, ISSELL, askFallbackPrice);
        FBAHeap.FBAOrder[] memory bids = FBAHeap.peekTopList(bidAm, asks[0].price, ISBUY, bidFallbackPrice);

        // TODO: replace with a dynamic array
        uint256[] memory prices = new uint256[](11);
        // prices: [95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105]
        for (uint256 i = 0; i < 11; i++) {
            prices[i] = 95 + i;
        }

        // First part: match orders with the same price
        for (uint256 i = 0; i < prices.length; i++) {
            uint256 price = prices[i];

            // Get all order indices with the same price
            (uint256[] memory bidIndices, uint256 nBids, uint256 bidTotalAmount) = getOrdersInfoAtPrice(bids, price);
            (uint256[] memory askIndices, uint256 nAsks, uint256 askTotalAmount) = getOrdersInfoAtPrice(asks, price);

            // Match orders with the same price
            uint256 fillRatio;
            if (bidTotalAmount > askTotalAmount) {
                // ask side is fully filled
                // ask side that has less amount
                for (uint256 j = 0; j < nAsks; j++) {
                    FBAHeap.deleteAtIndex(ISSELL, askAm, askMm, askIndices[j]);
                }
                // bid side that has more amount
                fillRatio = askTotalAmount / bidTotalAmount;
                for (uint256 j = 0; j < nBids; j++) {
                    FBAHeap.FBAOrder memory order = bids[bidIndices[j]];
                    order.amount -= fillRatio * order.amount;
                    FBAHeap.updateOrder(bidAm, order, bidIndices[j]);
                }
                fills.push(Fill(askTotalAmount, price));
            } else if (bidTotalAmount < askTotalAmount) {
                // bid side is fully filled
                // bid side that has less amount
                for (uint256 j = 0; j < nBids; j++) {
                    FBAHeap.deleteAtIndex(ISBUY, bidAm, bidMm, bidIndices[j]);
                }
                // ask side that has more amount
                fillRatio = bidTotalAmount / askTotalAmount;
                for (uint256 j = 0; j < nAsks; j++) {
                    FBAHeap.FBAOrder memory order = asks[askIndices[j]];
                    order.amount -= fillRatio * order.amount;
                    FBAHeap.updateOrder(askAm, order, askIndices[j]);
                }
                fills.push(Fill(bidTotalAmount, price));
            } else {
                // both sides are fully filled
                for (uint256 j = 0; j < nAsks; j++) {
                    FBAHeap.deleteAtIndex(ISSELL, askAm, askMm, askIndices[j]);
                }
                for (uint256 j = 0; j < nBids; j++) {
                    FBAHeap.deleteAtIndex(ISBUY, bidAm, bidMm, bidIndices[j]);
                }
                fills.push(Fill(askTotalAmount, price));
            }
        }

        // Second part: match orders with different prices
        // ...

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
        emit OrderPlace(result.price, result.side, result.amount);
    }

    function cancelOrderCallback(CancelResult memory result) public payable {
        emit OrderCancel(result.clientId, result.side);
    }
}
