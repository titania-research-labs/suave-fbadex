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

    // Simplifies placeOrder logic, will not actually be used for publicly storing fills!
    Fill[] public fills;

    struct Fill {
        uint amount;
        uint price;
    }
    struct PlaceResult {
        uint256 price;
        bool side;
        uint256 amount;
    }
    struct CancelResult {
        uint256 price;
        bool side;
        uint256 amount;
    }

    event FillEvent(Fill);
    event OrderPlace(uint256 price, bool side, uint256 amount);
    event OrderCancel(uint256 price, bool side, uint256 amount);

    constructor() {
        addressList = new address[](1);
        // from Suave.sol: address public constant ANYALLOWED = 0xC8df3686b4Afb2BB53e60EAe97EF043FE03Fb829;
        addressList[0] = 0xC8df3686b4Afb2BB53e60EAe97EF043FE03Fb829;
    }

    function initFBA() external returns (bytes memory) {
        // For the array
        Suave.DataRecord memory bidArr = Suave.newDataRecord(
            0,
            addressList,
            addressList,
            "suaveFBA:v0:dataId"
        );
        FBAHeap.ArrayMetadata memory bidAm = FBAHeap.ArrayMetadata(
            0,
            bidArr.id
        );
        FBAHeap.arrSetMetadata(bidAm);

        Suave.DataRecord memory askArr = Suave.newDataRecord(
            0,
            addressList,
            addressList,
            "suaveFBA:v0:dataId"
        );
        FBAHeap.ArrayMetadata memory askAm = FBAHeap.ArrayMetadata(
            0,
            askArr.id
        );
        FBAHeap.arrSetMetadata(askAm);

        // For the map
        Suave.DataRecord memory bidMap = Suave.newDataRecord(
            0,
            addressList,
            addressList,
            "suaveFBA:v0:dataId"
        );
        FBAHeap.MapMetadata memory bidMm = FBAHeap.MapMetadata(bidMap.id);
        FBAHeap.mapSetMetadata(bidMm);

        Suave.DataRecord memory askMap = Suave.newDataRecord(
            0,
            addressList,
            addressList,
            "suaveFBA:v0:dataId"
        );
        FBAHeap.MapMetadata memory askMm = FBAHeap.MapMetadata(askMap.id);
        FBAHeap.mapSetMetadata(askMm);

        return
            abi.encodeWithSelector(
                this.initFBACallback.selector,
                bidArr.id,
                askArr.id,
                bidMap.id,
                askMap.id
            );
    }

    function displayFills(Fill[] memory _fills) public payable {
        for (uint256 i = 0; i < _fills.length; i++) {
            console.log(_fills[i].amount, _fills[i].price);
            emit FillEvent(_fills[i]);
        }
    }

    function placeOrderCallback(
        PlaceResult memory orderResult,
        Fill[] memory _fills
    ) public payable {
        emit OrderPlace(
            orderResult.price,
            orderResult.side,
            orderResult.amount
        );
        displayFills(_fills);
    }

    function cancelOrderCallback(
        CancelResult memory orderResult
    ) public payable {
        emit OrderCancel(
            orderResult.price,
            orderResult.side,
            orderResult.amount
        );
    }

    function initFBACallback(
        Suave.DataId _bidArrayRef,
        Suave.DataId _askArrayRef,
        Suave.DataId _bidMapRef,
        Suave.DataId _askMapRef
    ) public payable {
        askArrayRef = _askArrayRef;
        askMapRef = _askMapRef;
        bidArrayRef = _bidArrayRef;
        bidMapRef = _bidMapRef;
    }

    /**
     * @notice Allows user to place a new order and immediately checks for fills
     */
    function placeOrder(
        FBAHeap.FBAOrder memory ord
    ) external returns (bytes memory) {
        FBAHeap.ArrayMetadata memory bidAm = FBAHeap.arrGetMetadata(
            bidArrayRef
        );
        FBAHeap.MapMetadata memory bidMm = FBAHeap.mapGetMetadata(bidMapRef);
        FBAHeap.ArrayMetadata memory askAm = FBAHeap.arrGetMetadata(
            askArrayRef
        );
        FBAHeap.MapMetadata memory askMm = FBAHeap.mapGetMetadata(askMapRef);

        bool maxHeapBids = true;
        bool maxHeapAsks = false;

        // Add it to bids or asks heap...
        if (ord.side == ISBUY) {
            FBAHeap.insertOrder(bidAm, bidMm, ord);
        } else if (ord.side == ISSELL) {
            FBAHeap.insertOrder(askAm, askMm, ord);
        }

        uint bidFallbackPrice = 0;
        uint askFallbackPrice = type(uint).max;
        FBAHeap.FBAOrder memory bestBid = FBAHeap.peek(
            bidAm,
            bidFallbackPrice,
            ISBUY
        );
        FBAHeap.FBAOrder memory bestAsk = FBAHeap.peek(
            askAm,
            askFallbackPrice,
            ISSELL
        );

        while (bestBid.price >= bestAsk.price) {
            uint fillAmount;
            uint fillPrice;

            if (ord.side == ISBUY) {
                fillPrice = bestAsk.price;
            } else {
                fillPrice = bestBid.price;
            }
            if (bestBid.amount < bestAsk.amount) {
                fillAmount = bestBid.amount;
                // If there's a fill it can only be with this order that
                // just came in, so use OPPOSITE price..
                // And append a fill to our fills list...
                FBAHeap.popOrder(maxHeapBids, bidAm, bidMm);
                // Need to overwrite the ask size
                bestAsk.amount = bestAsk.amount - fillAmount;
                FBAHeap.updateOrder(askAm, bestAsk, 0);
                // And now get the next bid for the next iteration...
                bestBid = FBAHeap.peek(bidAm, bidFallbackPrice, ISBUY);
            } else if (bestAsk.amount < bestBid.amount) {
                fillAmount = bestAsk.amount;
                FBAHeap.popOrder(maxHeapAsks, askAm, askMm);
                // Need to overwrite the ask size
                bestBid.amount = bestBid.amount - fillAmount;
                FBAHeap.updateOrder(bidAm, bestBid, 0);
                bestAsk = FBAHeap.peek(askAm, askFallbackPrice, ISSELL);
            } else {
                fillAmount = bestAsk.amount;
                FBAHeap.popOrder(maxHeapBids, bidAm, bidMm);
                FBAHeap.popOrder(maxHeapAsks, askAm, askMm);
                bestBid = FBAHeap.peek(bidAm, bidFallbackPrice, ISBUY);
                bestAsk = FBAHeap.peek(askAm, askFallbackPrice, ISSELL);
            }
            // And append a fill to our fills list...
            Fill memory fill = Fill(fillAmount, fillPrice);
            fills.push(fill);
        }

        // Assuming order placement was always successful?
        PlaceResult memory pr = PlaceResult(ord.price, ord.side, ord.amount);
        return
            abi.encodeWithSelector(this.placeOrderCallback.selector, pr, fills);
    }

    /**
     * @notice Allows user to cancel an order they previously placed
     */
    function cancelOrder(
        string memory clientId,
        bool side
    ) external returns (bytes memory) {
        FBAHeap.FBAOrder memory ord;

        if (side == ISBUY) {
            bool maxHeapBids = true;
            FBAHeap.ArrayMetadata memory bidAm = FBAHeap.arrGetMetadata(
                bidArrayRef
            );
            FBAHeap.MapMetadata memory bidMm = FBAHeap.mapGetMetadata(
                bidMapRef
            );
            ord = FBAHeap.deleteOrder(maxHeapBids, bidAm, bidMm, clientId);
        } else if (side == ISSELL) {
            bool maxHeapAsks = false;
            FBAHeap.ArrayMetadata memory askAm = FBAHeap.arrGetMetadata(
                askArrayRef
            );
            FBAHeap.MapMetadata memory askMm = FBAHeap.mapGetMetadata(
                askMapRef
            );
            ord = FBAHeap.deleteOrder(maxHeapAsks, askAm, askMm, clientId);
        }

        CancelResult memory orderResult = CancelResult(
            ord.price,
            ord.side,
            ord.amount
        );
        return
            abi.encodeWithSelector(
                this.cancelOrderCallback.selector,
                orderResult
            );
    }
}
