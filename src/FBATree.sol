// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "suave-std/suavelib/Suave.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "forge-std/console.sol";

// Library with a binary search tree specifically built for a limit orderbook

library FBATree {
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

    // map will track the root node of the tree
    struct MapMetadata {
        Suave.DataId ref;
    }

    // tree will store the actual orders
    struct TreeMetadata {
        Suave.DataId ref;
    }

    //////////// Helper functions specific to FBA
    function insertOrder(
        TreeMetadata memory tm,
        MapMetadata memory mm,
        FBAOrder memory ord
    ) internal {
        // If side is 'true' it's bid side, and we have a max tree, otherwise asks and min tree
        bool maxTree = ord.side;

        bytes memory val = abi.encode(ord);

        // Insert into the tree
        insertNode(tm, mm, ord.price, val);
    }

    /**
     * @notice To delete we will find the node of the order and then remove it
     */
    function deleteOrder(
        bool maxTree,
        TreeMetadata memory tm,
        MapMetadata memory mm,
        string memory clientId
    ) internal returns (FBAOrder memory) {
        bytes memory indBytes = mapGet(mm, clientId);
        uint256 price = abi.decode(indBytes, (uint256));
        FBAOrder memory ord = deleteNode(maxTree, tm, mm, price);
        return ord;
    }

    /**
     * @notice Same idea as delete but it will always be the root node
     */
    function popOrder(
        bool maxTree,
        TreeMetadata memory tm,
        MapMetadata memory mm
    ) internal {
        deleteRoot(maxTree, tm, mm);
    }

    /**
     * @notice Returns best bid/ask if exists, otherwise creates an element with extreme price
     */
    function peek(
        TreeMetadata memory tm,
        uint fallbackPrice,
        bool fallbackSide
    ) internal returns (FBAOrder memory) {
        // So if tree is empty create a new struct with the fallback values
        if (tm.ref == 0) {
            return FBAOrder(fallbackPrice, fallbackSide, 0, "");
        }

        bytes memory ordBytes = getRoot(tm);
        FBAOrder memory ord = abi.decode(ordBytes, (FBAOrder));
        return ord;
    }

    /**
     * @notice Overwrites data for a specified order
     */
    function updateOrder(
        TreeMetadata memory tm,
        FBAOrder memory ord,
        uint256 price
    ) internal {
        // Update the node with the new order
        updateNode(tm, price, abi.encode(ord));
    }

    //////////// Tree methods
    /**
     * @notice Inserts a new node into the tree
     */
    function insertNode(
        TreeMetadata memory tm,
        MapMetadata memory mm,
        uint256 price,
        bytes memory value
    ) private {
        // If the tree is empty, set the root
        if (tm.ref == 0) {
            Suave.confidentialStore(tm.ref, "root", value);
            mapWrite(mm, Strings.toString(price), value);
            return;
        }

        // Otherwise, recursively insert the node
        insertNodeRecursive(tm, mm, price, value, "root");
    }

    function insertNodeRecursive(
        TreeMetadata memory tm,
        MapMetadata memory mm,
        uint256 price,
        bytes memory value,
        string memory key
    ) private {
        bytes memory nodeBytes = Suave.confidentialRetrieve(tm.ref, key);
        if (nodeBytes.length == 0) {
            // New node, write it
            Suave.confidentialStore(tm.ref, key, value);
            mapWrite(mm, Strings.toString(price), value);
            return;
        }

        FBAOrder memory node = abi.decode(nodeBytes, (FBAOrder));
        if (price < node.price) {
            // Insert left
            insertNodeRecursive(tm, mm, price, value, Strings.toString(uint256(keccak256(abi.encodePacked(key, "left")))));
        } else {
            // Insert right
            insertNodeRecursive(tm, mm, price, value, Strings.toString(uint256(keccak256(abi.encodePacked(key, "right")))));
        }
    }

    /**
     * @notice Deletes a node from the tree
     */
    function deleteNode(
        bool maxTree,
        TreeMetadata memory tm,
        MapMetadata memory mm,
        uint256 price
    ) private returns (FBAOrder memory) {
        // Find the node
        bytes memory nodeBytes = getNode(tm, Strings.toString(price));
        FBAOrder memory ord = abi.decode(nodeBytes, (FBAOrder));

        // Delete the node
        deleteNodeRecursive(tm, mm, Strings.toString(price), "root");

        return ord;
    }

    function deleteNodeRecursive(
        TreeMetadata memory tm,
        MapMetadata memory mm,
        string memory key,
        string memory parent
    ) private {
        bytes memory nodeBytes = Suave.confidentialRetrieve(tm.ref, key);
        if (nodeBytes.length == 0) {
            return;
        }

        FBAOrder memory node = abi.decode(nodeBytes, (FBAOrder));
        string memory leftKey = Strings.toString(uint256(keccak256(abi.encodePacked(key, "left"))));
        string memory rightKey = Strings.toString(uint256(keccak256(abi.encodePacked(key, "right"))));

        // If the node has no children, delete it
        if (Suave.confidentialRetrieve(tm.ref, leftKey).length == 0 && Suave.confidentialRetrieve(tm.ref, rightKey).length == 0) {
            Suave.confidentialStore(tm.ref, key, new bytes(0));
            mapDel(mm, Strings.toString(node.price));
            if (keccak256(abi.encodePacked(key)) != keccak256(abi.encodePacked("root"))) {
                // Update the parent
                updateParent(tm, mm, parent, key, new bytes(0));
            }
            return;
        }

        // If the node has one child, replace it with the child
        if (Suave.confidentialRetrieve(tm.ref, leftKey).length == 0) {
            Suave.confidentialStore(tm.ref, key, Suave.confidentialRetrieve(tm.ref, rightKey));
            updateParent(tm, mm, parent, key, Suave.confidentialRetrieve(tm.ref, rightKey));
            Suave.confidentialStore(tm.ref, rightKey, new bytes(0));
            mapDel(mm, Strings.toString(node.price));
            return;
        }
        if (Suave.confidentialRetrieve(tm.ref, rightKey).length == 0) {
            Suave.confidentialStore(tm.ref, key, Suave.confidentialRetrieve(tm.ref, leftKey));
            updateParent(tm, mm, parent, key, Suave.confidentialRetrieve(tm.ref, leftKey));
            Suave.confidentialStore(tm.ref, leftKey, new bytes(0));
            mapDel(mm, Strings.toString(node.price));
            return;
        }

        // If the node has two children, replace it with the in-order successor
        bytes memory successorBytes = getMinNode(tm, rightKey);
        FBAOrder memory successor = abi.decode(successorBytes, (FBAOrder));
        Suave.confidentialStore(tm.ref, key, successorBytes);
        updateParent(tm, mm, parent, key, successorBytes);
        deleteNodeRecursive(tm, mm, rightKey, key);
        mapDel(mm, Strings.toString(node.price));
        mapWrite(mm, Strings.toString(successor.price), successorBytes);
    }

    /**
     * @notice Deletes the root node of the tree
     */
    function deleteRoot(
        bool maxTree,
        TreeMetadata memory tm,
        MapMetadata memory mm
    ) private {
        deleteNodeRecursive(tm, mm, "root", "");
    }

    /**
     * @notice Gets the root node of the tree
     */
    function getRoot(TreeMetadata memory tm) private returns (bytes memory) {
        return Suave.confidentialRetrieve(tm.ref, "root");
    }

    /**
     * @notice Gets a node from the tree
     */
    function getNode(
        TreeMetadata memory tm,
        string memory key
    ) private returns (bytes memory) {
        return Suave.confidentialRetrieve(tm.ref, key);
    }

    /**
     * @notice Gets the minimum node in the tree
     */
    function getMinNode(
        TreeMetadata memory tm,
        string memory key
    ) private returns (bytes memory) {
        string memory leftKey = Strings.toString(uint256(keccak256(abi.encodePacked(key, "left"))));
        if (Suave.confidentialRetrieve(tm.ref, leftKey).length == 0) {
            return Suave.confidentialRetrieve(tm.ref, key);
        }
        return getMinNode(tm, leftKey);
    }

    /**
     * @notice Updates a node in the tree
     */
    function updateNode(
        TreeMetadata memory tm,
        uint256 price,
        bytes memory value
    ) private {
        string memory key = Strings.toString(price);
        Suave.confidentialStore(tm.ref, key, value);
    }

    /**
     * @notice Updates the parent of a node
     */
    function updateParent(
        TreeMetadata memory tm,
        MapMetadata memory mm,
        string memory parent,
        string memory key,
        bytes memory value
    ) private {
        if (keccak256(abi.encodePacked(parent)) == keccak256(abi.encodePacked("root"))) {
            Suave.confidentialStore(tm.ref, "root", value);
            return;
        }

        string memory parentKey = parent;
        string memory childKey = key;
        if (keccak256(abi.encodePacked(childKey)) < keccak256(abi.encodePacked(parentKey))) {
            Suave.confidentialStore(tm.ref, Strings.toString(uint256(keccak256(abi.encodePacked(parentKey, "left")))), value);
        } else {
            Suave.confidentialStore(tm.ref, Strings.toString(uint256(keccak256(abi.encodePacked(parentKey, "right")))), value);
        }
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
}
