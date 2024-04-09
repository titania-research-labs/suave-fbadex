// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "suave-std/suavelib/Suave.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "forge-std/console.sol";

// Library with a heap specifically built for a limit orderbook

library LOBHeap {
    // TODO - switch bool side to be this enum
    // enum Side {BID, ASK}
    // Currently all orders are GTC limit orders
    struct LOBOrder {
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

    //////////// Helper functions specific to LOB
    function insertOrder(
        ArrayMetadata memory am,
        MapMetadata memory mm,
        LOBOrder memory ord
    ) internal {
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
    function deleteOrder(
        bool maxHeap,
        ArrayMetadata memory am,
        MapMetadata memory mm,
        string memory clientId
    ) internal returns (LOBOrder memory) {
        bytes memory indBytes = mapGet(mm, clientId);
        uint256 ind = abi.decode(indBytes, (uint256));
        LOBOrder memory ord = deleteAtIndex(maxHeap, am, mm, ind);
        return ord;
    }

    /**
     * @notice Same idea as delete but it will always be the element at index 0
     */
    function popOrder(
        bool maxHeap,
        ArrayMetadata memory am,
        MapMetadata memory mm
    ) internal {
        deleteAtIndex(maxHeap, am, mm, 0);
    }

    /**
     * @notice Returns best bid/ask if exists, otherwise creates an element with extreme price
     */
    function peek(
        ArrayMetadata memory am,
        uint fallbackPrice,
        bool fallbackSide
    ) internal returns (LOBOrder memory) {
        // So if heap is empty create a new struct with the fallback values
        if (am.length == 0) {
            return LOBOrder(fallbackPrice, fallbackSide, 0, "");
        }

        bytes memory ordBytes = arrGet(am, 0);
        LOBOrder memory ord = abi.decode(ordBytes, (LOBOrder));
        return ord;
    }

    /**
     * @notice Overwrites data for a specified order
     */
    function updateOrder(
        ArrayMetadata memory am,
        LOBOrder memory ord,
        uint index
    ) internal {
        // Index will remain the same so we don't need to update our map here
        bytes memory val = abi.encode(ord);
        arrWrite(am, index, val);
    }

    //////////// Map methods
    /**
     * @notice Retreives map info.  This must be obtained in order to interact with map
     */
    function mapGetMetadata(
        Suave.DataId ref
    ) internal returns (MapMetadata memory) {
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
    function mapGet(
        MapMetadata memory mm,
        string memory key
    ) internal returns (bytes memory) {
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
    function mapWrite(
        MapMetadata memory mm,
        string memory key,
        bytes memory value
    ) internal {
        Suave.confidentialStore(mm.ref, key, value);
    }

    /**
     * @notice Deletes value at a key
     */
    function mapDel(MapMetadata memory mm, string memory key) internal {
        // TODO - if a user wanted to write this as a value, map would fail,
        // can we track deleted keys instead?
        bytes memory noBytes = new bytes(0);
        mapWrite(mm, key, noBytes);
    }

    //////////// Array methods
    /**
     * @notice Retreives array info.  This must be obtained in order to interact with array
     */
    function arrGetMetadata(
        Suave.DataId ref
    ) internal returns (ArrayMetadata memory) {
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
    function arrGet(
        ArrayMetadata memory am,
        uint256 index
    ) internal returns (bytes memory) {
        string memory indexStr = Strings.toString(index);
        bytes memory val = Suave.confidentialRetrieve(am.ref, indexStr);
        return val;
    }

    /**
     * @notice Appends to end of array and returns current array length
     */
    function arrAppend(
        ArrayMetadata memory am,
        bytes memory value
    ) internal returns (uint256) {
        arrWrite(am, am.length, value);
        am.length += 1;
        arrSetMetadata(am);
        return am.length;
    }

    /**
     * @notice Overwrite an element at specified index
     */
    function arrWrite(
        ArrayMetadata memory am,
        uint256 index,
        bytes memory value
    ) internal {
        require(index <= am.length, "Index out of bounds");
        string memory indexStr = Strings.toString(index);
        Suave.confidentialStore(am.ref, indexStr, value);
    }

    /**
     * @notice Deletes an element from the array while preserving ordering
     * @dev Moves all elements one to the left, so O(n) and be careful with large arrays
     */
    function arrDel(ArrayMetadata memory am, uint256 index) internal {
        for (uint256 i = index; i < am.length - 1; i++) {
            arrWrite(am, i, arrGet(am, i + 1));
        }
        am.length -= 1;
        arrSetMetadata(am);
    }

    /**
     * @notice Deletes an element at a specified index and then maintains heap
     */
    function deleteAtIndex(
        bool maxHeap,
        ArrayMetadata memory am,
        MapMetadata memory mm,
        uint256 index
    ) internal returns (LOBOrder memory) {
        require(index < am.length, "Index out of bounds");
        uint256 lastIndex = am.length - 1;

        // TODO - should this be at the end?
        am.length -= 1;
        arrSetMetadata(am);

        // Get the item we're deleting to return it
        bytes memory ordBytesDel = arrGet(am, lastIndex);
        LOBOrder memory deletedItem = abi.decode(ordBytesDel, (LOBOrder));

        // TODO - Are we deleting the map value here?  Or is deletion implicit?
        // mapWrite(mm, ordBytesDel.clientId, abi.encode(index));

        if (index != lastIndex) {
            // Copy final value to current index...
            bytes memory ordBytes = arrGet(am, lastIndex);
            LOBOrder memory ord = abi.decode(ordBytes, (LOBOrder));
            arrWrite(am, index, ordBytes);
            mapWrite(mm, ord.clientId, abi.encode(index));

            // Need to see if we need to heapify up/down
            uint256 indexCompare = (index - 1) / 2;
            bytes memory ordBytesComp = arrGet(am, indexCompare);
            LOBOrder memory ordComp = abi.decode(ordBytesComp, (LOBOrder));

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
    function heapifyUp(
        bool maxHeap,
        ArrayMetadata memory am,
        MapMetadata memory mm,
        uint256 index
    ) private {
        // Sorting based on price - but depending on whether bids or asks we
        // need to sort in different directions
        while (index > 0) {
            uint256 indexParent = (index - 1) / 2;
            bytes memory ordBytes = arrGet(am, index);
            bytes memory ordParentBytes = arrGet(am, indexParent);
            // need to decode values
            LOBOrder memory ord = abi.decode(ordBytes, (LOBOrder));
            LOBOrder memory ordParent = abi.decode(ordParentBytes, (LOBOrder));

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
    function heapifyDown(
        bool maxHeap,
        ArrayMetadata memory am,
        MapMetadata memory mm,
        uint256 index
    ) private {
        uint256 leftChildInd;
        uint256 rightChildInd;
        uint256 largestInd;
        uint256 lastInd = am.length - 1;

        bytes memory ordBytes = arrGet(am, index);
        LOBOrder memory ord = abi.decode(ordBytes, (LOBOrder));

        LOBOrder memory ordLargest = ord;
        bytes memory ordLargestBytes = ordBytes;

        while (true) {
            leftChildInd = index * 2 + 1;
            rightChildInd = index * 2 + 2;
            largestInd = index;

            if (leftChildInd <= lastInd) {
                bytes memory ordChildBytes = arrGet(am, leftChildInd);
                LOBOrder memory ordChild = abi.decode(
                    ordChildBytes,
                    (LOBOrder)
                );

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
                LOBOrder memory ordChild = abi.decode(
                    ordChildBytes,
                    (LOBOrder)
                );
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
