// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "suave-std/Test.sol";
import "suave-std/suavelib/Suave.sol";
import "forge-std/console.sol";
import {LOBHeap} from "../src/LOBHeap.sol";

contract TestForge is Test, SuaveEnabled {
    function deployHeap()
        internal
        returns (LOBHeap.ArrayMetadata memory am, LOBHeap.MapMetadata memory mm)
    {
        // Initializing library
        // No contract, just test library functionality
        address[] memory addressList;
        addressList = new address[](1);
        addressList[0] = 0xC8df3686b4Afb2BB53e60EAe97EF043FE03Fb829;
        // For the array
        Suave.DataRecord memory record1 = Suave.newDataRecord(
            0,
            addressList,
            addressList,
            "suaveLOB:v0:dataId"
        );
        am = LOBHeap.ArrayMetadata(0, record1.id);
        LOBHeap.arrSetMetadata(am);
        // For the map
        Suave.DataRecord memory record2 = Suave.newDataRecord(
            0,
            addressList,
            addressList,
            "suaveLOB:v0:dataId"
        );
        mm = LOBHeap.MapMetadata(record2.id);
        LOBHeap.mapSetMetadata(mm);
    }

    function testInsertOrder() public {
        (
            LOBHeap.ArrayMetadata memory am,
            LOBHeap.MapMetadata memory mm
        ) = deployHeap();
        LOBHeap.LOBOrder memory ord = LOBHeap.LOBOrder(100, false, 123, "abcd");

        LOBHeap.insertOrder(am, mm, ord);

        uint bidFallbackPrice = 0;

        LOBHeap.LOBOrder memory ord2 = LOBHeap.peek(
            am,
            bidFallbackPrice,
            false
        );
        console.log(ord.amount, ord.price, ord.clientId);
        console.log(ord2.amount, ord2.price, ord2.clientId);
    }

    function testDeleteOrder() public {
        (
            LOBHeap.ArrayMetadata memory am,
            LOBHeap.MapMetadata memory mm
        ) = deployHeap();

        LOBHeap.LOBOrder memory ord = LOBHeap.LOBOrder(100, true, 123, "abcd");
        LOBHeap.LOBOrder memory ord2 = LOBHeap.LOBOrder(101, true, 456, "efgh");

        bool maxHeap = true;
        LOBHeap.insertOrder(am, mm, ord);
        LOBHeap.insertOrder(am, mm, ord2);
        LOBHeap.deleteOrder(maxHeap, am, mm, ord.clientId);

        uint askFallbackPrice = type(uint).max;
        LOBHeap.LOBOrder memory ord3 = LOBHeap.peek(am, askFallbackPrice, true);
        console.log(ord3.amount, ord3.price, ord3.clientId);
    }

    function testBidsSorting() public {
        // Want to make sure that when we insert bids vs asks we're sorting properly
        // (bids should be a max heap, asks a min heap)
        (
            LOBHeap.ArrayMetadata memory am,
            LOBHeap.MapMetadata memory mm
        ) = deployHeap();
        // This is just the 0/1 flag indicating that these are buy orders
        bool buy = true;
        // Insert three orders, make sure we see max at end
        // When we peek, we should see the 104 one...
        LOBHeap.LOBOrder memory ord1 = LOBHeap.LOBOrder(99, buy, 123, "abcd");
        LOBHeap.LOBOrder memory ord2 = LOBHeap.LOBOrder(104, buy, 123, "defg");
        LOBHeap.LOBOrder memory ord3 = LOBHeap.LOBOrder(100, buy, 123, "hijk");

        LOBHeap.insertOrder(am, mm, ord1);
        LOBHeap.insertOrder(am, mm, ord2);
        LOBHeap.insertOrder(am, mm, ord3);

        uint bidFallbackPrice = 0;
        LOBHeap.LOBOrder memory ordTop = LOBHeap.peek(
            am,
            bidFallbackPrice,
            true
        );
        console.log(ordTop.amount, ordTop.price, ordTop.clientId);
        console.log(ord2.amount, ord2.price, ord2.clientId);
        assertEq(ordTop.price, ord2.price);
    }

    function testAsksSorting() public {
        (
            LOBHeap.ArrayMetadata memory am,
            LOBHeap.MapMetadata memory mm
        ) = deployHeap();
        // This is just the 0/1 flag indicating that these are sell orders
        bool sell = false;
        // Insert three orders, make sure we see min at end
        // When we peek, we should see the 95 one...
        LOBHeap.LOBOrder memory ord1 = LOBHeap.LOBOrder(99, sell, 123, "abcd");
        LOBHeap.LOBOrder memory ord2 = LOBHeap.LOBOrder(95, sell, 123, "defg");
        LOBHeap.LOBOrder memory ord3 = LOBHeap.LOBOrder(100, sell, 123, "hijk");
        LOBHeap.insertOrder(am, mm, ord1);
        LOBHeap.insertOrder(am, mm, ord2);
        LOBHeap.insertOrder(am, mm, ord3);

        uint bidFallbackPrice = 0;
        LOBHeap.LOBOrder memory ordTop = LOBHeap.peek(
            am,
            bidFallbackPrice,
            false
        );
        console.log(ordTop.amount, ordTop.price, ordTop.clientId);
        console.log(ord2.amount, ord2.price, ord2.clientId);
        assertEq(ordTop.price, ord2.price);
    }
}
