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

        // Add it to bids or asks heap...
        if (ord.side == ISBUY) {
            FBAHeap.insertOrder(bidAm, bidMm, ord);
        } else if (ord.side == ISSELL) {
            FBAHeap.insertOrder(askAm, askMm, ord);
        }

        // Assuming order placement was always successful?
        PlaceResult memory pr = PlaceResult(ord.price, ord.side, ord.amount);
        return
            abi.encodeWithSelector(this.placeOrderCallback.selector, pr);
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

    function executeFills() external returns (bytes memory) {
        FBAHeap.ArrayMetadata memory bidAm = FBAHeap.arrGetMetadata(
            bidArrayRef
        );
        FBAHeap.MapMetadata memory bidMm = FBAHeap.mapGetMetadata(bidMapRef);
        FBAHeap.ArrayMetadata memory askAm = FBAHeap.arrGetMetadata(
            askArrayRef
        );
        FBAHeap.MapMetadata memory askMm = FBAHeap.mapGetMetadata(askMapRef);

        uint bidFallbackPrice = 0;
        uint askFallbackPrice = type(uint).max;
        FBAHeap.FBAOrder memory bestBid = FBAHeap.peekTopOne(
            bidAm,
            bidFallbackPrice,
            ISBUY
        );
        // asks and bids are the orders that will be possibly matched
        FBAHeap.FBAOrder[] memory asks = FBAHeap.peekTopList(askAm, bestBid.price, ISSELL, askFallbackPrice);
        FBAHeap.FBAOrder[] memory bids = FBAHeap.peekTopList(bidAm, asks[0].price, ISBUY, bidFallbackPrice);

        // First part: match orders with the same price
        for (uint i = 0; i < bids.length; i++) {
            uint fillAmount;
            uint fillPrice;
            for (uint j = 0; j < asks.length; j++) {
                if (bids[i].price == asks[j].price) {
                    fillPrice = bids[i].price;
                    if (bids[i].amount > asks[j].amount) {
                        fillAmount = asks[j].amount;
                        // ask side: delete order at index j
                        asks[j].amount = 0;
                        FBAHeap.deleteAtIndex(ISSELL, askAm, askMm, j);
                        // bid side: update order at index i
                        bids[i].amount -= fillAmount;
                        FBAHeap.updateOrder(bidAm, bids[i], i);
                    } else if (bids[i].amount < asks[j].amount) {
                        fillAmount = bids[i].amount;
                        // bid side: delete order at index i
                        bids[i].amount = 0;
                        FBAHeap.deleteAtIndex(ISBUY, bidAm, bidMm, i);
                        // ask side: update order at index j
                        asks[j].amount -= fillAmount;
                        FBAHeap.updateOrder(askAm, asks[j], j);
                    } else {
                        fillAmount = bids[i].amount;
                        // bid side: delete order at index i
                        bids[i].amount = 0;
                        FBAHeap.deleteAtIndex(ISBUY, bidAm, bidMm, i);
                        // ask side: delete order at index j
                        asks[j].amount = 0;
                        FBAHeap.deleteAtIndex(ISSELL, askAm, askMm, j);
                    }
                    break;
                }
            }
            // If no match was found, continue to the next bid
            if (fillAmount == 0) {
                continue;
            }
            // And append a fill to our fills list...
            Fill memory fill = Fill(fillAmount, fillPrice);
            fills.push(fill);
        }

        // Second part: match orders with different prices
        // ...

        return abi.encodeWithSelector(this.executeFillsCallback.selector, fills);
    }

    function executeFillsCallback(
        Fill[] memory _fills
    ) public payable {
        displayFills(_fills);
    }

    //////////// Callback methods

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

    function placeOrderCallback(
        PlaceResult memory orderResult
    ) public payable {
        emit OrderPlace(
            orderResult.price,
            orderResult.side,
            orderResult.amount
        );
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
}
