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

    function testInsertBidOrder() public {
        bool side = true; // bid side
        (FBAHeap.ArrayMetadata memory am, FBAHeap.MapMetadata memory mm) = deployHeap();

        FBAHeap.Order memory insertedOrd = FBAHeap.Order(100, 123, side, "order1");
        FBAHeap.insertOrder(insertedOrd, am, mm);

        FBAHeap.Order memory peekedOrd = FBAHeap.getTopOrder(am, side);

        assertEq(insertedOrd.amount, peekedOrd.amount);
        assertEq(insertedOrd.price, peekedOrd.price);
        assertEq(insertedOrd.orderId, peekedOrd.orderId);
    }

    function testInsertAskOrder() public {
        bool side = false; // ask side
        (FBAHeap.ArrayMetadata memory am, FBAHeap.MapMetadata memory mm) = deployHeap();

        FBAHeap.Order memory insertedOrd = FBAHeap.Order(100, 123, side, "order1");
        FBAHeap.insertOrder(insertedOrd, am, mm);

        FBAHeap.Order memory peekedOrd = FBAHeap.getTopOrder(am, side);

        assertEq(insertedOrd.amount, peekedOrd.amount);
        assertEq(insertedOrd.price, peekedOrd.price);
        assertEq(insertedOrd.orderId, peekedOrd.orderId);
    }

    function testInsertBidOrderList() public {
        bool side = true; // bid side
        (FBAHeap.ArrayMetadata memory am, FBAHeap.MapMetadata memory mm) = deployHeap();

        FBAHeap.Order memory insertedOrd1 = FBAHeap.Order(101, 100, side, "order1");
        FBAHeap.Order memory insertedOrd2 = FBAHeap.Order(102, 200, side, "order2");
        FBAHeap.Order memory insertedOrd3 = FBAHeap.Order(103, 300, side, "order3");
        FBAHeap.Order memory insertedOrd4 = FBAHeap.Order(104, 400, side, "order4");
        FBAHeap.Order memory insertedOrd5 = FBAHeap.Order(105, 500, side, "order5");
        FBAHeap.insertOrder(insertedOrd1, am, mm);
        FBAHeap.insertOrder(insertedOrd2, am, mm);
        FBAHeap.insertOrder(insertedOrd3, am, mm);
        FBAHeap.insertOrder(insertedOrd4, am, mm);
        FBAHeap.insertOrder(insertedOrd5, am, mm);

        FBAHeap.Order memory peekedOrd = FBAHeap.getTopOrder(am, side);

        assertEq(insertedOrd5.amount, peekedOrd.amount);
        assertEq(insertedOrd5.price, peekedOrd.price);
        assertEq(insertedOrd5.orderId, peekedOrd.orderId);
    }

    function testInsertAskOrderList() public {
        bool side = false; // ask side
        (FBAHeap.ArrayMetadata memory am, FBAHeap.MapMetadata memory mm) = deployHeap();

        FBAHeap.Order memory insertedOrd1 = FBAHeap.Order(105, 100, side, "order1");
        FBAHeap.Order memory insertedOrd2 = FBAHeap.Order(104, 200, side, "order2");
        FBAHeap.Order memory insertedOrd3 = FBAHeap.Order(103, 300, side, "order3");
        FBAHeap.Order memory insertedOrd4 = FBAHeap.Order(102, 400, side, "order4");
        FBAHeap.Order memory insertedOrd5 = FBAHeap.Order(101, 500, side, "order5");
        FBAHeap.insertOrder(insertedOrd1, am, mm);
        FBAHeap.insertOrder(insertedOrd2, am, mm);
        FBAHeap.insertOrder(insertedOrd3, am, mm);
        FBAHeap.insertOrder(insertedOrd4, am, mm);
        FBAHeap.insertOrder(insertedOrd5, am, mm);

        FBAHeap.Order memory peekedOrd = FBAHeap.getTopOrder(am, side);

        assertEq(insertedOrd5.amount, peekedOrd.amount);
        assertEq(insertedOrd5.price, peekedOrd.price);
        assertEq(insertedOrd5.orderId, peekedOrd.orderId);
    }

    function testDeleteBidOrder() public {
        bool side = true; // bid side
        (FBAHeap.ArrayMetadata memory am, FBAHeap.MapMetadata memory mm) = deployHeap();

        FBAHeap.Order memory insertedOrd1 = FBAHeap.Order(100, 123, side, "order1");
        FBAHeap.Order memory insertedOrd2 = FBAHeap.Order(101, 456, side, "order2");

        FBAHeap.insertOrder(insertedOrd1, am, mm);
        FBAHeap.insertOrder(insertedOrd2, am, mm);
        FBAHeap.deleteOrder(insertedOrd2.orderId, side, am, mm);

        FBAHeap.Order memory peekedOrd = FBAHeap.getTopOrder(am, side);

        assertEq(insertedOrd1.amount, peekedOrd.amount);
        assertEq(insertedOrd1.price, peekedOrd.price);
        assertEq(insertedOrd1.orderId, peekedOrd.orderId);
    }

    function testDeleteAskOrder() public {
        bool side = false; // ask side
        (FBAHeap.ArrayMetadata memory am, FBAHeap.MapMetadata memory mm) = deployHeap();

        FBAHeap.Order memory insertedOrd1 = FBAHeap.Order(101, 456, side, "order2");
        FBAHeap.Order memory insertedOrd2 = FBAHeap.Order(100, 123, side, "order1");

        FBAHeap.insertOrder(insertedOrd1, am, mm);
        FBAHeap.insertOrder(insertedOrd2, am, mm);
        FBAHeap.deleteOrder(insertedOrd2.orderId, side, am, mm);

        FBAHeap.Order memory peekedOrd = FBAHeap.getTopOrder(am, side);

        assertEq(insertedOrd1.amount, peekedOrd.amount);
        assertEq(insertedOrd1.price, peekedOrd.price);
        assertEq(insertedOrd1.orderId, peekedOrd.orderId);
    }

    function testBidsSorting() public {
        // Want to make sure that when we insert bids vs asks we're sorting properly
        bool side = true; // bid side
        (FBAHeap.ArrayMetadata memory am, FBAHeap.MapMetadata memory mm) = deployHeap();
        // This is just the 0/1 flag indicating that these are buy orders
        // Insert three orders, make sure we see max at end
        // When we peek, we should see the 104 one...
        FBAHeap.Order memory insertedOrd1 = FBAHeap.Order(99, 123, side, "order1");
        FBAHeap.Order memory insertedOrd2 = FBAHeap.Order(104, 123, side, "order2");
        FBAHeap.Order memory insertedOrd3 = FBAHeap.Order(102, 123, side, "order3");

        FBAHeap.insertOrder(insertedOrd1, am, mm);
        FBAHeap.insertOrder(insertedOrd2, am, mm);
        FBAHeap.insertOrder(insertedOrd3, am, mm);

        FBAHeap.Order[] memory peekedOrds = FBAHeap.getTopOrderList(100, side, am);

        assertEq(peekedOrds.length, 2);
        assertEq(insertedOrd2.amount, peekedOrds[0].amount);
        assertEq(insertedOrd2.price, peekedOrds[0].price);
        assertEq(insertedOrd2.orderId, peekedOrds[0].orderId);
        assertEq(insertedOrd3.amount, peekedOrds[1].amount);
        assertEq(insertedOrd3.price, peekedOrds[1].price);
        assertEq(insertedOrd3.orderId, peekedOrds[1].orderId);
    }

    function testAsksSorting() public {
        bool side = false; // ask side
        (FBAHeap.ArrayMetadata memory am, FBAHeap.MapMetadata memory mm) = deployHeap();
        // This is just the 0/1 flag indicating that these are sell orders
        // Insert three orders, make sure we see min at end
        // When we peek, we should see the 95 one...
        FBAHeap.Order memory insertedOrd1 = FBAHeap.Order(97, 123, side, "order1");
        FBAHeap.Order memory insertedOrd2 = FBAHeap.Order(95, 123, side, "order2");
        FBAHeap.Order memory insertedOrd3 = FBAHeap.Order(100, 123, side, "order3");
        FBAHeap.insertOrder(insertedOrd1, am, mm);
        FBAHeap.insertOrder(insertedOrd2, am, mm);
        FBAHeap.insertOrder(insertedOrd3, am, mm);

        FBAHeap.Order[] memory peekedOrds = FBAHeap.getTopOrderList(99, side, am);

        assertEq(peekedOrds.length, 2);
        assertEq(insertedOrd2.amount, peekedOrds[0].amount);
        assertEq(insertedOrd2.price, peekedOrds[0].price);
        assertEq(insertedOrd2.orderId, peekedOrds[0].orderId);
        assertEq(insertedOrd1.amount, peekedOrds[1].amount);
        assertEq(insertedOrd1.price, peekedOrds[1].price);
        assertEq(insertedOrd1.orderId, peekedOrds[1].orderId);
    }
}
