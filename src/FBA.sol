// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {FBAHeap} from "../src/FBAHeap.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "forge-std/console.sol";
import "suave-std/suavelib/Suave.sol";

contract FBA {
    bool ISBUY = true;
    bool ISSELL = false;

    address[] addressList;

    // Need to maintain separate heaps for bids and asks
    Suave.DataId public askArrayRef;
    Suave.DataId public askMapRef;
    Suave.DataId public bidArrayRef;
    Suave.DataId public bidMapRef;

    // Fills and cancels
    Fill[] public fills; // This array length will be reset to 0 at the beginning of each `executeFills`
    Cancel[] public cancels; // This array length will be reset to 0 at the end of each cancel operation in `executeFills`

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
     * @notice Allows user to place a new order
     */
    function placeOrder(FBAHeap.Order memory ord) external returns (bytes memory) {
        (FBAHeap.ArrayMetadata memory am, FBAHeap.MapMetadata memory mm) = getMetadata(ord.side);
        FBAHeap.insertOrder(ord, am, mm);

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
        (FBAHeap.ArrayMetadata memory bidAm, FBAHeap.MapMetadata memory bidMm) = getMetadata(ISBUY);
        (FBAHeap.ArrayMetadata memory askAm, FBAHeap.MapMetadata memory askMm) = getMetadata(ISSELL);

        // Reset fills
        fills = new Fill[](0);

        ////// First part: prioritize cancels
        for (uint256 i = 0; i < cancels.length; i++) {
            string memory orderId = cancels[i].orderId;
            bool side = cancels[i].side;

            if (side == ISBUY) {
                FBAHeap.deleteOrder(orderId, side, bidAm, bidMm);
            } else if (side == ISSELL) {
                FBAHeap.deleteOrder(orderId, side, askAm, askMm);
            }
        }
        cancels = new Cancel[](0);

        ////// Second part: match orders
        FBAHeap.Order memory bidMax = FBAHeap.getTopOrder(bidAm, ISBUY);
        FBAHeap.Order memory askMin = FBAHeap.getTopOrder(askAm, ISSELL);
        uint256 clearingPrice = (bidMax.price + askMin.price) / 2;
        // Match orders as long as:
        // 1. The highest bid is less than the lowest ask
        // 2. The clearing price is less than the highest bid and greater than the lowest ask
        while (bidMax.price >= askMin.price && bidMax.price >= clearingPrice && askMin.price <= clearingPrice) {
            if (bidMax.amount > askMin.amount) {
                fills.push(Fill(clearingPrice, askMin.amount));
                bidMax.amount -= askMin.amount;
                FBAHeap.updateOrder(bidMax, bidAm, bidMm);
                FBAHeap.deleteOrder(askMin.orderId, ISSELL, askAm, askMm);
            } else if (bidMax.amount < askMin.amount) {
                fills.push(Fill(clearingPrice, bidMax.amount));
                askMin.amount -= bidMax.amount;
                FBAHeap.updateOrder(askMin, askAm, askMm);
                FBAHeap.deleteOrder(bidMax.orderId, ISBUY, bidAm, bidMm);
            } else {
                fills.push(Fill(clearingPrice, bidMax.amount));
                FBAHeap.deleteOrder(bidMax.orderId, ISBUY, bidAm, bidMm);
                FBAHeap.deleteOrder(askMin.orderId, ISSELL, askAm, askMm);
            }

            // Update bidMax and askMin
            bidMax = FBAHeap.getTopOrder(bidAm, ISBUY);
            askMin = FBAHeap.getTopOrder(askAm, ISSELL);
        }

        return abi.encodeWithSelector(this.executeFillsCallback.selector, fills);
    }

    //////////// Internal methods

    /**
     * @notice Returns the metadata of the array and map
     */
    function getMetadata(bool side) internal returns (FBAHeap.ArrayMetadata memory, FBAHeap.MapMetadata memory) {
        if (side == ISBUY) {
            return (FBAHeap.arrGetMetadata(bidArrayRef), FBAHeap.mapGetMetadata(bidMapRef));
        } else if (side == ISSELL) {
            return (FBAHeap.arrGetMetadata(askArrayRef), FBAHeap.mapGetMetadata(askMapRef));
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
