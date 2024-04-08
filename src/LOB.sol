// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "suave-std/suavelib/Suave.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {LOBHeap} from "../src/LOBHeap.sol";

contract LOB {
    bool ISBUY = true;
    bool ISSELL = false;

    address[] addressList;

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

    Fill[] public fills;
    // event FillEvent(Fill[] fills);
    event FillEvent(Fill);

    event OrderPlace(uint256 price, bool side, uint256 amount);
    event OrderCancel(uint256 price, bool side, uint256 amount);

    // Need to maintain separate heaps for bids and asks
    Suave.DataId public askArrayRef;
    Suave.DataId public askMapRef;
    Suave.DataId public bidArrayRef;
    Suave.DataId public bidMapRef;

    constructor() {
        addressList = new address[](1);
        // from Suave.sol: address public constant ANYALLOWED = 0xC8df3686b4Afb2BB53e60EAe97EF043FE03Fb829;
        addressList[0] = 0xC8df3686b4Afb2BB53e60EAe97EF043FE03Fb829;
    }

    function initLOB() external returns (bytes memory) {
        // For the array
        Suave.DataRecord memory bidArr = Suave.newDataRecord(
            0,
            addressList,
            addressList,
            "suaveLOB:v0:dataId"
        );
        LOBHeap.ArrayMetadata memory bidAm = LOBHeap.ArrayMetadata(
            0,
            bidArr.id
        );
        LOBHeap.arrSetMetadata(bidAm);

        Suave.DataRecord memory askArr = Suave.newDataRecord(
            0,
            addressList,
            addressList,
            "suaveLOB:v0:dataId"
        );
        LOBHeap.ArrayMetadata memory askAm = LOBHeap.ArrayMetadata(
            0,
            askArr.id
        );
        LOBHeap.arrSetMetadata(askAm);

        // For the map
        Suave.DataRecord memory bidMap = Suave.newDataRecord(
            0,
            addressList,
            addressList,
            "suaveLOB:v0:dataId"
        );
        LOBHeap.MapMetadata memory bidMm = LOBHeap.MapMetadata(bidMap.id);
        LOBHeap.mapSetMetadata(bidMm);

        Suave.DataRecord memory askMap = Suave.newDataRecord(
            0,
            addressList,
            addressList,
            "suaveLOB:v0:dataId"
        );
        LOBHeap.MapMetadata memory askMm = LOBHeap.MapMetadata(askMap.id);
        LOBHeap.mapSetMetadata(askMm);

        return
            abi.encodeWithSelector(
                this.initLOBCallback.selector,
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

    function nullCallback() public payable {}

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

    function initLOBCallback(
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
        LOBHeap.LOBOrder memory ord
    ) external returns (bytes memory) {
        LOBHeap.ArrayMetadata memory bidAm = LOBHeap.arrGetMetadata(
            bidArrayRef
        );
        LOBHeap.MapMetadata memory bidMm = LOBHeap.mapGetMetadata(bidMapRef);
        LOBHeap.ArrayMetadata memory askAm = LOBHeap.arrGetMetadata(
            askArrayRef
        );
        LOBHeap.MapMetadata memory askMm = LOBHeap.mapGetMetadata(askMapRef);

        // Add it to bids or asks heap...
        if (ord.side == ISBUY) {
            LOBHeap.insertOrder(bidAm, bidMm, ord);
        } else if (ord.side == ISSELL) {
            LOBHeap.insertOrder(askAm, askMm, ord);
        }

        uint bidFallbackPrice = 0;
        uint askFallbackPrice = type(uint).max;
        LOBHeap.LOBOrder memory bestBid = LOBHeap.peek(
            bidAm,
            bidFallbackPrice,
            ISBUY
        );
        LOBHeap.LOBOrder memory bestAsk = LOBHeap.peek(
            askAm,
            askFallbackPrice,
            ISSELL
        );

        // Fill[] memory fills;

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
                LOBHeap.popOrder(bidAm, bidMm);
                // Need to overwrite the ask size
                bestAsk.amount = bestAsk.amount - fillAmount;
                LOBHeap.updateOrder(askAm, bestAsk, 0);
                // And now get the next bid for the next iteration...
                bestBid = LOBHeap.peek(bidAm, bidFallbackPrice, ISBUY);
            } else if (bestAsk.amount < bestBid.amount) {
                fillAmount = bestAsk.amount;
                LOBHeap.popOrder(askAm, askMm);
                // Need to overwrite the ask size
                bestBid.amount = bestBid.amount - fillAmount;
                LOBHeap.updateOrder(bidAm, bestBid, 0);
                bestAsk = LOBHeap.peek(askAm, askFallbackPrice, ISSELL);
            } else {
                fillAmount = bestAsk.amount;
                LOBHeap.popOrder(bidAm, bidMm);
                LOBHeap.popOrder(askAm, askMm);
                bestBid = LOBHeap.peek(bidAm, bidFallbackPrice, ISBUY);
                bestAsk = LOBHeap.peek(askAm, askFallbackPrice, ISSELL);
            }
            // And append a fill to our fills list...
            Fill memory fill = Fill(fillAmount, fillPrice);
            // fills.push(fill);
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
        LOBHeap.LOBOrder memory ord;
        if (side == ISBUY) {
            LOBHeap.ArrayMetadata memory bidAm = LOBHeap.arrGetMetadata(
                bidArrayRef
            );
            LOBHeap.MapMetadata memory bidMm = LOBHeap.mapGetMetadata(
                bidMapRef
            );
            ord = LOBHeap.deleteOrder(bidAm, bidMm, clientId);
        } else if (side == ISSELL) {
            LOBHeap.ArrayMetadata memory askAm = LOBHeap.arrGetMetadata(
                askArrayRef
            );
            LOBHeap.MapMetadata memory askMm = LOBHeap.mapGetMetadata(
                askMapRef
            );
            ord = LOBHeap.deleteOrder(askAm, askMm, clientId);
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
