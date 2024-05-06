// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "suave-std/suavelib/Suave.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "forge-std/console.sol";

// Library with a heap specifically built for a limit orderbook

library FBAHeap {
    // TODO - switch bool side to be this enum
    // enum Side {BID, ASK}

    // Currently all orders are GTC limit orders
    struct FBAOrder {
        uint256 price;
        // 'true' for bids and 'false' for asks
        bool side;
        uint256 amount;
        string clientId;
    }

    // map will track the indices of the orders
    struct MapMetadata {
        Suave.DataId ref;
    }

    // array will store the actual orders
    struct ArrayMetadata {
        uint256 length;
        Suave.DataId ref;
    }

    //////////// Helper functions specific to FBA
    function insertOrder(FBAOrder memory ord, ArrayMetadata memory am, MapMetadata memory mm) internal {
        // If side is 'true' it's bid side, and we have a max heap, otherwise asks and min heap
        bool isMaxHeap = ord.side;

        bytes memory val = abi.encode(ord);

        // Append AND set index
        uint256 arrLen = arrAppend(val, am);

        // Want our map to be from clientId to array index
        // Want to store the index here, not arrLen, so subtract 1
        bytes memory val2 = abi.encode(arrLen - 1);
        mapWrite(ord.clientId, val2, mm);

        heapifyUp(arrLen - 1, isMaxHeap, am, mm);
    }

    /**
     * @notice To delete we will find the index of the order and then overwrite at that index
     */
    function deleteOrder(string memory clientId, bool isMaxHeap, ArrayMetadata memory am, MapMetadata memory mm)
        internal
        returns (FBAOrder memory)
    {
        bytes memory indexBytes = mapGet(clientId, mm);
        uint256 index = abi.decode(indexBytes, (uint256));
        FBAOrder memory ord = deleteAtIndex(index, isMaxHeap, am, mm);
        return ord;
    }

    /**
     * @notice Returns best bid/ask if exists, otherwise creates an element with extreme price
     */
    function getTopOrder(ArrayMetadata memory am, bool fallbackSide, uint256 fallbackPrice)
        internal
        returns (FBAOrder memory)
    {
        // So if heap is empty create a new struct with the fallback values
        if (am.length == 0) {
            return FBAOrder(fallbackPrice, fallbackSide, 0, "");
        }

        FBAOrder memory ord = getOrder(0, am);
        return ord;
    }

    /**
     * @notice Returns all bids/asks above or below a threshold
     */
    function getTopOrderList(uint256 threshold, bool side, ArrayMetadata memory am, uint256 fallbackPrice)
        internal
        returns (FBAOrder[] memory)
    {
        // So if heap is empty create a new struct with the fallback values
        if (am.length == 0) {
            FBAOrder[] memory fallbackOrders = new FBAOrder[](1);
            fallbackOrders[0] = FBAOrder(fallbackPrice, side, 0, "");
            return fallbackOrders;
        }

        // Count the number of orders above the threshold
        uint256 count = 0;
        for (uint256 i = 0; i < am.length; i++) {
            FBAOrder memory ord = getOrder(i, am);
            if (isFirstLarger(ord.price, threshold, side)) {
                count++;
            }
        }

        // Create an array to store the orders above the threshold
        FBAOrder[] memory orders = new FBAOrder[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < am.length; i++) {
            FBAOrder memory ord = getOrder(i, am);
            if (isFirstLarger(ord.price, threshold, side)) {
                orders[index] = ord;
                index++;
            }
        }

        return orders;
    }

    /**
     * @notice Overwrites data for a specified order
     */
    function updateOrder(FBAOrder memory ord, uint256 index, ArrayMetadata memory am) internal {
        // Index will remain the same so we don't need to update our map here
        bytes memory val = abi.encode(ord);
        arrWrite(index, val, am);
    }

    function getOrder(uint256 index, ArrayMetadata memory am) internal returns (FBAOrder memory) {
        bytes memory ordBytes = arrGet(index, am);
        FBAOrder memory ord = abi.decode(ordBytes, (FBAOrder));
        return ord;
    }

    //////////// Map methods
    /**
     * @notice Retreives map info.  This must be obtained in order to interact with map
     */
    function mapGetMetadata(Suave.DataId ref) internal returns (MapMetadata memory) {
        bytes memory val = Suave.confidentialRetrieve(ref, "metadata");
        MapMetadata memory am = abi.decode(val, (MapMetadata));
        return am;
    }

    /**
     * @notice Overwrites map info
     */
    function mapSetMetadata(MapMetadata memory am) internal {
        Suave.confidentialStore(am.ref, "metadata", abi.encode(am));
    }

    /**
     * @notice Retrieves element corresponding to key
     */
    function mapGet(string memory key, MapMetadata memory mm) internal returns (bytes memory) {
        bytes memory val = Suave.confidentialRetrieve(mm.ref, key);
        // For consistency throw here - if we've deleted we'll have bytes(0),
        // If key doesn't exist we'll get a different failure, but want error each time
        bytes memory noBytes = new bytes(0);
        require(val.length != noBytes.length, "Key not found");
        return val;
    }

    /**
     * @notice Writes key+value
     */
    function mapWrite(string memory key, bytes memory value, MapMetadata memory mm) internal {
        Suave.confidentialStore(mm.ref, key, value);
    }

    //////////// Array methods
    /**
     * @notice Retreives array info.  This must be obtained in order to interact with array
     */
    function arrGetMetadata(Suave.DataId ref) internal returns (ArrayMetadata memory) {
        bytes memory val = Suave.confidentialRetrieve(ref, "metadata");
        ArrayMetadata memory am = abi.decode(val, (ArrayMetadata));
        return am;
    }

    /**
     * @notice Overwrites array info
     */
    function arrSetMetadata(ArrayMetadata memory am) internal {
        Suave.confidentialStore(am.ref, "metadata", abi.encode(am));
    }

    /**
     * @notice Retrieves element at specific index
     */
    function arrGet(uint256 index, ArrayMetadata memory am) internal returns (bytes memory) {
        string memory indexStr = Strings.toString(index);
        bytes memory val = Suave.confidentialRetrieve(am.ref, indexStr);
        return val;
    }

    /**
     * @notice Appends to end of array and returns current array length
     */
    function arrAppend(bytes memory value, ArrayMetadata memory am) internal returns (uint256) {
        arrWrite(am.length, value, am);
        am.length += 1;
        arrSetMetadata(am);
        return am.length;
    }

    /**
     * @notice Overwrite an element at specified index
     */
    function arrWrite(uint256 index, bytes memory value, ArrayMetadata memory am) internal {
        require(index <= am.length, "Index out of bounds");
        string memory indexStr = Strings.toString(index);
        Suave.confidentialStore(am.ref, indexStr, value);
    }

    /**
     * @notice Deletes an element at a specified index and then maintains heap
     */
    function deleteAtIndex(uint256 index, bool isMaxHeap, ArrayMetadata memory am, MapMetadata memory mm)
        internal
        returns (FBAOrder memory)
    {
        require(index < am.length, "Index out of bounds");
        uint256 lastIndex = am.length - 1;

        // TODO - should this be at the end?
        am.length -= 1;
        arrSetMetadata(am);

        // Get the item we're deleting to return it
        FBAOrder memory deletedItem = getOrder(index, am);

        // TODO - Are we deleting the map value here?  Or is deletion implicit?
        // mapWrite(deletedItem.clientId, abi.encode(index), mm);

        // if the index is last, ...
        if (index == lastIndex) {
            return deletedItem;
        } else if (index == 0) {
            heapifyDown(index, isMaxHeap, am, mm);
            return deletedItem;
        }

        // Copy final value to current index...
        bytes memory ordBytes = arrGet(lastIndex, am);
        FBAOrder memory ord = abi.decode(ordBytes, (FBAOrder));
        arrWrite(index, ordBytes, am);
        mapWrite(ord.clientId, abi.encode(index), mm);

        // Need to see if we need to heapify up/down
        uint256 indexParent = (index - 1) / 2;
        FBAOrder memory ordParent = getOrder(indexParent, am);

        if (isFirstLarger(ordParent.price, ord.price, isMaxHeap)) {
            heapifyDown(index, isMaxHeap, am, mm);
        } else {
            heapifyUp(index, isMaxHeap, am, mm);
        }
        // Think we do NOT need to pop?
        // else {
        //     heap.pop();
        // }

        return deletedItem;
    }

    /**
     * @notice Maintains heap invariant by moving elements up
     */
    function heapifyUp(uint256 index, bool isMaxHeap, ArrayMetadata memory am, MapMetadata memory mm) private {
        // Sorting based on price - but depending on whether bids or asks we
        // need to sort in different directions
        while (index > 0) {
            uint256 indexParent = (index - 1) / 2;
            bytes memory ordBytes = arrGet(index, am);
            bytes memory ordParentBytes = arrGet(indexParent, am);
            // need to decode values
            FBAOrder memory ord = abi.decode(ordBytes, (FBAOrder));
            FBAOrder memory ordParent = abi.decode(ordParentBytes, (FBAOrder));

            if (isFirstLarger(ordParent.price, ord.price, isMaxHeap)) {
                break;
            }

            // Flip values to maintain heap
            arrWrite(index, ordParentBytes, am);
            arrWrite(indexParent, ordBytes, am);
            // And we need to flip map values too...
            mapWrite(ord.clientId, abi.encode(indexParent), mm);
            mapWrite(ordParent.clientId, abi.encode(index), mm);

            index = indexParent;
        }
    }

    /**
     * @notice Maintains heap invariant by moving elements down
     */
    function heapifyDown(uint256 index, bool isMaxHeap, ArrayMetadata memory am, MapMetadata memory mm) private {
        uint256 leftChildIndex;
        uint256 rightChildIndex;
        uint256 largestIndex;
        uint256 lastIndex = am.length - 1;

        bytes memory ordBytes = arrGet(index, am);
        FBAOrder memory ord = abi.decode(ordBytes, (FBAOrder));

        bytes memory ordLargestBytes = ordBytes;
        FBAOrder memory ordLargest = ord;

        while (true) {
            leftChildIndex = index * 2 + 1;
            rightChildIndex = index * 2 + 2;
            largestIndex = index;

            if (leftChildIndex <= lastIndex) {
                bytes memory ordChildBytes = arrGet(leftChildIndex, am);
                FBAOrder memory ordChild = abi.decode(ordChildBytes, (FBAOrder));

                // Again sorting based on min/max heap
                if (isFirstLarger(ordChild.price, ordLargest.price, isMaxHeap)) {
                    ordLargestBytes = ordChildBytes;
                    ordLargest = ordChild;
                    largestIndex = leftChildIndex;
                }
            }

            if (rightChildIndex <= lastIndex) {
                bytes memory ordChildBytes = arrGet(rightChildIndex, am);
                FBAOrder memory ordChild = abi.decode(ordChildBytes, (FBAOrder));
                if (isFirstLarger(ordChild.price, ordLargest.price, isMaxHeap)) {
                    ordLargestBytes = ordChildBytes;
                    ordLargest = ordChild;
                    largestIndex = rightChildIndex;
                }
            }

            // Once our starting value is max one, heap invariant is met
            if (largestIndex == index) {
                break;
            }

            // Switch largest with our index
            arrWrite(index, ordLargestBytes, am);
            arrWrite(largestIndex, ordBytes, am);
            // And we need to flip map values too...
            mapWrite(ord.clientId, abi.encode(largestIndex), mm);
            mapWrite(ordLargest.clientId, abi.encode(index), mm);

            index = largestIndex;
        }
    }

    function isFirstLarger(uint256 first, uint256 second, bool isMaxHeap)
        internal
        pure
        returns (bool)
    {
        if (isMaxHeap) {
            return first >= second;
        } else {
            return first <= second;
        }
    }
}
