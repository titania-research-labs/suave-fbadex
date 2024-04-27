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
    function insertOrder(ArrayMetadata memory am, MapMetadata memory mm, FBAOrder memory ord) internal {
        // If side is 'true' it's bid side, and we have a max heap, otherwise asks and min heap
        bool maxHeap = ord.side;

        bytes memory val = abi.encode(ord);

        // Append AND set index
        uint256 arrLen = arrAppend(am, val);

        // Want our map to be from clientId to array index
        // Want to store the index here, not arrLen, so subtract 1
        bytes memory val2 = abi.encode(arrLen - 1);
        mapWrite(mm, ord.clientId, val2);

        heapifyUp(maxHeap, am, mm, arrLen - 1);
    }

    /**
     * @notice To delete we will find the index of the order and then overwrite at that index
     */
    function deleteOrder(bool maxHeap, ArrayMetadata memory am, MapMetadata memory mm, string memory clientId)
        internal
        returns (FBAOrder memory)
    {
        bytes memory indBytes = mapGet(mm, clientId);
        uint256 ind = abi.decode(indBytes, (uint256));
        FBAOrder memory ord = deleteAtIndex(maxHeap, am, mm, ind);
        return ord;
    }

    /**
     * @notice Same idea as delete but it will always be the element at index 0
     */
    function popOrder(bool maxHeap, ArrayMetadata memory am, MapMetadata memory mm) internal {
        deleteAtIndex(maxHeap, am, mm, 0);
    }

    /**
     * @notice Returns best bid/ask if exists, otherwise creates an element with extreme price
     */
    function peekTopOne(ArrayMetadata memory am, uint256 fallbackPrice, bool fallbackSide)
        internal
        returns (FBAOrder memory)
    {
        // So if heap is empty create a new struct with the fallback values
        if (am.length == 0) {
            return FBAOrder(fallbackPrice, fallbackSide, 0, "");
        }

        bytes memory ordBytes = arrGet(am, 0);
        FBAOrder memory ord = abi.decode(ordBytes, (FBAOrder));
        return ord;
    }

    /**
     * @notice Returns all bids/asks above or below a threshold
     */
    function peekTopList(ArrayMetadata memory am, uint256 threshold, bool side, uint256 fallbackPrice)
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
            bytes memory ordBytes = arrGet(am, i);
            FBAOrder memory ord = abi.decode(ordBytes, (FBAOrder));
            if (side && (ord.price >= threshold)) {
                count++;
            } else if (!side && (ord.price <= threshold)) {
                count++;
            }
        }

        // Create an array to store the orders above the threshold
        FBAOrder[] memory orders = new FBAOrder[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < am.length; i++) {
            bytes memory ordBytes = arrGet(am, i);
            FBAOrder memory ord = abi.decode(ordBytes, (FBAOrder));
            if (side && (ord.price >= threshold)) {
                orders[index] = ord;
                index++;
            } else if (!side && (ord.price <= threshold)) {
                orders[index] = ord;
                index++;
            }
        }

        return orders;
    }

    /**
     * @notice Overwrites data for a specified order
     */
    function updateOrder(ArrayMetadata memory am, FBAOrder memory ord, uint256 index) internal {
        // Index will remain the same so we don't need to update our map here
        bytes memory val = abi.encode(ord);
        arrWrite(am, index, val);
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
    function mapGet(MapMetadata memory mm, string memory key) internal returns (bytes memory) {
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
    function mapWrite(MapMetadata memory mm, string memory key, bytes memory value) internal {
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
    function arrGet(ArrayMetadata memory am, uint256 index) internal returns (bytes memory) {
        string memory indexStr = Strings.toString(index);
        bytes memory val = Suave.confidentialRetrieve(am.ref, indexStr);
        return val;
    }

    /**
     * @notice Appends to end of array and returns current array length
     */
    function arrAppend(ArrayMetadata memory am, bytes memory value) internal returns (uint256) {
        arrWrite(am, am.length, value);
        am.length += 1;
        arrSetMetadata(am);
        return am.length;
    }

    /**
     * @notice Overwrite an element at specified index
     */
    function arrWrite(ArrayMetadata memory am, uint256 index, bytes memory value) internal {
        require(index <= am.length, "Index out of bounds");
        string memory indexStr = Strings.toString(index);
        Suave.confidentialStore(am.ref, indexStr, value);
    }

    /**
     * @notice Deletes an element at a specified index and then maintains heap
     */
    function deleteAtIndex(bool maxHeap, ArrayMetadata memory am, MapMetadata memory mm, uint256 index)
        internal
        returns (FBAOrder memory)
    {
        require(index < am.length, "Index out of bounds");
        uint256 lastIndex = am.length - 1;

        // TODO - should this be at the end?
        am.length -= 1;
        arrSetMetadata(am);

        // Get the item we're deleting to return it
        bytes memory ordBytesDel = arrGet(am, lastIndex);
        FBAOrder memory deletedItem = abi.decode(ordBytesDel, (FBAOrder));

        // TODO - Are we deleting the map value here?  Or is deletion implicit?
        // mapWrite(mm, ordBytesDel.clientId, abi.encode(index));

        if (index != lastIndex) {
            // Copy final value to current index...
            bytes memory ordBytes = arrGet(am, lastIndex);
            FBAOrder memory ord = abi.decode(ordBytes, (FBAOrder));
            arrWrite(am, index, ordBytes);
            mapWrite(mm, ord.clientId, abi.encode(index));

            // Need to see if we need to heapify up/down
            uint256 indexCompare = (index - 1) / 2;
            bytes memory ordBytesComp = arrGet(am, indexCompare);
            FBAOrder memory ordComp = abi.decode(ordBytesComp, (FBAOrder));

            if (index == 0 || ord.price <= ordComp.price) {
                heapifyDown(maxHeap, am, mm, index);
            } else {
                heapifyUp(maxHeap, am, mm, index);
            }
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
    function heapifyUp(bool maxHeap, ArrayMetadata memory am, MapMetadata memory mm, uint256 index) private {
        // Sorting based on price - but depending on whether bids or asks we
        // need to sort in different directions
        while (index > 0) {
            uint256 indexParent = (index - 1) / 2;
            bytes memory ordBytes = arrGet(am, index);
            bytes memory ordParentBytes = arrGet(am, indexParent);
            // need to decode values
            FBAOrder memory ord = abi.decode(ordBytes, (FBAOrder));
            FBAOrder memory ordParent = abi.decode(ordParentBytes, (FBAOrder));

            // Sort one way or the other based on min/max heap
            if (maxHeap && ord.price <= ordParent.price) {
                break;
            } else if (!maxHeap && ord.price >= ordParent.price) {
                break;
            }

            // Flip values to maintain heap
            arrWrite(am, index, ordParentBytes);
            arrWrite(am, indexParent, ordBytes);
            // And we need to flip map values too...
            mapWrite(mm, ord.clientId, abi.encode(indexParent));
            mapWrite(mm, ordParent.clientId, abi.encode(index));

            index = indexParent;
        }
    }

    /**
     * @notice Maintains heap invariant by moving elements down
     */
    function heapifyDown(bool maxHeap, ArrayMetadata memory am, MapMetadata memory mm, uint256 index) private {
        uint256 leftChildInd;
        uint256 rightChildInd;
        uint256 largestInd;
        uint256 lastInd = am.length - 1;

        bytes memory ordBytes = arrGet(am, index);
        FBAOrder memory ord = abi.decode(ordBytes, (FBAOrder));

        FBAOrder memory ordLargest = ord;
        bytes memory ordLargestBytes = ordBytes;

        while (true) {
            leftChildInd = index * 2 + 1;
            rightChildInd = index * 2 + 2;
            largestInd = index;

            if (leftChildInd <= lastInd) {
                bytes memory ordChildBytes = arrGet(am, leftChildInd);
                FBAOrder memory ordChild = abi.decode(ordChildBytes, (FBAOrder));

                // Again sorting based on min/max heap
                if (maxHeap && ordChild.price > ordLargest.price) {
                    ordLargestBytes = ordChildBytes;
                    ordLargest = ordChild;
                    largestInd = leftChildInd;
                } else if (!maxHeap && ordChild.price < ordLargest.price) {
                    ordLargestBytes = ordChildBytes;
                    ordLargest = ordChild;
                    largestInd = leftChildInd;
                }
            }

            if (rightChildInd <= lastInd) {
                bytes memory ordChildBytes = arrGet(am, rightChildInd);
                FBAOrder memory ordChild = abi.decode(ordChildBytes, (FBAOrder));
                if (maxHeap && ordChild.price > ordLargest.price) {
                    ordLargestBytes = ordChildBytes;
                    ordLargest = ordChild;
                    largestInd = rightChildInd;
                } else if (!maxHeap && ordChild.price > ordLargest.price) {
                    ordLargestBytes = ordChildBytes;
                    ordLargest = ordChild;
                    largestInd = rightChildInd;
                }
            }

            // Once our starting value is max one, heap invariant is met
            if (largestInd == index) {
                break;
            }

            // Switch largest with our index
            arrWrite(am, index, ordLargestBytes);
            arrWrite(am, largestInd, ordBytes);
            // And we need to flip map values too...
            mapWrite(mm, ord.clientId, abi.encode(largestInd));
            mapWrite(mm, ordLargest.clientId, abi.encode(index));

            index = largestInd;
        }
    }
}
