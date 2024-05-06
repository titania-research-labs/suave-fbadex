// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "suave-std/Test.sol";
import "suave-std/suavelib/Suave.sol";
import "forge-std/console.sol";
import {FBAHeap} from "../src/FBAHeap.sol";

contract TestForge is Test, SuaveEnabled {
    function deployHeap() internal returns (FBAHeap.ArrayMetadata memory am, FBAHeap.MapMetadata memory mm) {
        // Initializing library
        // No contract, just test library functionality
        address[] memory addressList;
        addressList = new address[](1);
        addressList[0] = 0xC8df3686b4Afb2BB53e60EAe97EF043FE03Fb829;
        // For the array
        Suave.DataRecord memory arrRecord = Suave.newDataRecord(0, addressList, addressList, "suaveFBA:v0:dataId");
        am = FBAHeap.ArrayMetadata(0, arrRecord.id);
        FBAHeap.arrSetMetadata(am);
        // For the map
        Suave.DataRecord memory mapRecord = Suave.newDataRecord(0, addressList, addressList, "suaveFBA:v0:dataId");
        mm = FBAHeap.MapMetadata(mapRecord.id);
        FBAHeap.mapSetMetadata(mm);
    }

    function getExtPrice(bool side) internal pure returns (uint256 extPrice) {
        if (side == true) {
            // bid side
            extPrice = 0;
        } else {
            // ask side
            extPrice = type(uint256).max;
        }
    }

    function testInsertBidOrder() public {
        bool side = true; // bid side
        (FBAHeap.ArrayMetadata memory am, FBAHeap.MapMetadata memory mm) = deployHeap();

        FBAHeap.FBAOrder memory insertedOrd = FBAHeap.FBAOrder(100, side, 123, "abcd");
        FBAHeap.insertOrder(insertedOrd, am, mm);

        FBAHeap.FBAOrder memory peekedOrd = FBAHeap.getTopOrder(am, side, getExtPrice(side));

        assertEq(insertedOrd.amount, peekedOrd.amount);
        assertEq(insertedOrd.price, peekedOrd.price);
        assertEq(insertedOrd.clientId, peekedOrd.clientId);
    }

    function testDeleteBidOrder() public {
        bool side = true; // bid side
        (FBAHeap.ArrayMetadata memory am, FBAHeap.MapMetadata memory mm) = deployHeap();

        FBAHeap.FBAOrder memory insertedOrd1 = FBAHeap.FBAOrder(100, side, 123, "abcd");
        FBAHeap.FBAOrder memory insertedOrd2 = FBAHeap.FBAOrder(101, side, 456, "efgh");

        FBAHeap.insertOrder(insertedOrd1, am, mm);
        FBAHeap.insertOrder(insertedOrd2, am, mm);
        FBAHeap.deleteOrder(insertedOrd1.clientId, side, am, mm);

        FBAHeap.FBAOrder memory peekedOrd = FBAHeap.getTopOrder(am, side, getExtPrice(side));

        assertEq(insertedOrd2.amount, peekedOrd.amount);
        assertEq(insertedOrd2.price, peekedOrd.price);
        assertEq(insertedOrd2.clientId, peekedOrd.clientId);
    }

    function testBidsSorting() public {
        // Want to make sure that when we insert bids vs asks we're sorting properly
        bool side = true; // bid side
        (FBAHeap.ArrayMetadata memory am, FBAHeap.MapMetadata memory mm) = deployHeap();
        // This is just the 0/1 flag indicating that these are buy orders
        // Insert three orders, make sure we see max at end
        // When we peek, we should see the 104 one...
        FBAHeap.FBAOrder memory insertedOrd1 = FBAHeap.FBAOrder(99, side, 123, "abcd");
        FBAHeap.FBAOrder memory insertedOrd2 = FBAHeap.FBAOrder(104, side, 123, "defg");
        FBAHeap.FBAOrder memory insertedOrd3 = FBAHeap.FBAOrder(102, side, 123, "hijk");

        FBAHeap.insertOrder(insertedOrd1, am, mm);
        FBAHeap.insertOrder(insertedOrd2, am, mm);
        FBAHeap.insertOrder(insertedOrd3, am, mm);

        FBAHeap.FBAOrder[] memory peekedOrds = FBAHeap.getTopOrderList(100, side, am, getExtPrice(side));

        assertEq(peekedOrds.length, 2);
        assertEq(insertedOrd2.amount, peekedOrds[0].amount);
        assertEq(insertedOrd2.price, peekedOrds[0].price);
        assertEq(insertedOrd2.clientId, peekedOrds[0].clientId);
        assertEq(insertedOrd3.amount, peekedOrds[1].amount);
        assertEq(insertedOrd3.price, peekedOrds[1].price);
        assertEq(insertedOrd3.clientId, peekedOrds[1].clientId);
    }

    function testAsksSorting() public {
        bool side = false; // ask side
        (FBAHeap.ArrayMetadata memory am, FBAHeap.MapMetadata memory mm) = deployHeap();
        // This is just the 0/1 flag indicating that these are sell orders
        // Insert three orders, make sure we see min at end
        // When we peek, we should see the 95 one...
        FBAHeap.FBAOrder memory insertedOrd1 = FBAHeap.FBAOrder(97, side, 123, "abcd");
        FBAHeap.FBAOrder memory insertedOrd2 = FBAHeap.FBAOrder(95, side, 123, "defg");
        FBAHeap.FBAOrder memory insertedOrd3 = FBAHeap.FBAOrder(100, side, 123, "hijk");
        FBAHeap.insertOrder(insertedOrd1, am, mm);
        FBAHeap.insertOrder(insertedOrd2, am, mm);
        FBAHeap.insertOrder(insertedOrd3, am, mm);

        FBAHeap.FBAOrder[] memory peekedOrds = FBAHeap.getTopOrderList(99, side, am, getExtPrice(side));

        assertEq(peekedOrds.length, 2);
        assertEq(insertedOrd2.amount, peekedOrds[0].amount);
        assertEq(insertedOrd2.price, peekedOrds[0].price);
        assertEq(insertedOrd2.clientId, peekedOrds[0].clientId);
        assertEq(insertedOrd1.amount, peekedOrds[1].amount);
        assertEq(insertedOrd1.price, peekedOrds[1].price);
        assertEq(insertedOrd1.clientId, peekedOrds[1].clientId);
    }
}
