// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "suave-std/Test.sol";
import "suave-std/suavelib/Suave.sol";
import "forge-std/console.sol";
import {FBAHeap} from "../src/FBAHeap.sol";

contract TestForge is Test, SuaveEnabled {
    function deployHeap()
        internal
        returns (FBAHeap.ArrayMetadata memory am, FBAHeap.MapMetadata memory mm)
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
            "suaveFBA:v0:dataId"
        );
        am = FBAHeap.ArrayMetadata(0, record1.id);
        FBAHeap.arrSetMetadata(am);
        // For the map
        Suave.DataRecord memory record2 = Suave.newDataRecord(
            0,
            addressList,
            addressList,
            "suaveFBA:v0:dataId"
        );
        mm = FBAHeap.MapMetadata(record2.id);
        FBAHeap.mapSetMetadata(mm);
    }

    function testInsertOrder() public {
        (
            FBAHeap.ArrayMetadata memory am,
            FBAHeap.MapMetadata memory mm
        ) = deployHeap();
        FBAHeap.FBAOrder memory ord = FBAHeap.FBAOrder(100, false, 123, "abcd");

        FBAHeap.insertOrder(am, mm, ord);

        uint bidFallbackPrice = 0;

        FBAHeap.FBAOrder memory ord2 = FBAHeap.peek(
            am,
            bidFallbackPrice,
            false
        );
        console.log(ord.amount, ord.price, ord.clientId);
        console.log(ord2.amount, ord2.price, ord2.clientId);
    }

    function testDeleteOrder() public {
        (
            FBAHeap.ArrayMetadata memory am,
            FBAHeap.MapMetadata memory mm
        ) = deployHeap();

        FBAHeap.FBAOrder memory ord = FBAHeap.FBAOrder(100, true, 123, "abcd");
        FBAHeap.FBAOrder memory ord2 = FBAHeap.FBAOrder(101, true, 456, "efgh");

        bool maxHeap = true;
        FBAHeap.insertOrder(am, mm, ord);
        FBAHeap.insertOrder(am, mm, ord2);
        FBAHeap.deleteOrder(maxHeap, am, mm, ord.clientId);

        uint askFallbackPrice = type(uint).max;
        FBAHeap.FBAOrder memory ord3 = FBAHeap.peek(am, askFallbackPrice, true);
        console.log(ord3.amount, ord3.price, ord3.clientId);
    }

    function testBidsSorting() public {
        // Want to make sure that when we insert bids vs asks we're sorting properly
        // (bids should be a max heap, asks a min heap)
        (
            FBAHeap.ArrayMetadata memory am,
            FBAHeap.MapMetadata memory mm
        ) = deployHeap();
        // This is just the 0/1 flag indicating that these are buy orders
        bool buy = true;
        // Insert three orders, make sure we see max at end
        // When we peek, we should see the 104 one...
        FBAHeap.FBAOrder memory ord1 = FBAHeap.FBAOrder(99, buy, 123, "abcd");
        FBAHeap.FBAOrder memory ord2 = FBAHeap.FBAOrder(104, buy, 123, "defg");
        FBAHeap.FBAOrder memory ord3 = FBAHeap.FBAOrder(100, buy, 123, "hijk");

        FBAHeap.insertOrder(am, mm, ord1);
        FBAHeap.insertOrder(am, mm, ord2);
        FBAHeap.insertOrder(am, mm, ord3);

        uint bidFallbackPrice = 0;
        FBAHeap.FBAOrder memory ordTop = FBAHeap.peek(
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
            FBAHeap.ArrayMetadata memory am,
            FBAHeap.MapMetadata memory mm
        ) = deployHeap();
        // This is just the 0/1 flag indicating that these are sell orders
        bool sell = false;
        // Insert three orders, make sure we see min at end
        // When we peek, we should see the 95 one...
        FBAHeap.FBAOrder memory ord1 = FBAHeap.FBAOrder(99, sell, 123, "abcd");
        FBAHeap.FBAOrder memory ord2 = FBAHeap.FBAOrder(95, sell, 123, "defg");
        FBAHeap.FBAOrder memory ord3 = FBAHeap.FBAOrder(100, sell, 123, "hijk");
        FBAHeap.insertOrder(am, mm, ord1);
        FBAHeap.insertOrder(am, mm, ord2);
        FBAHeap.insertOrder(am, mm, ord3);

        uint bidFallbackPrice = 0;
        FBAHeap.FBAOrder memory ordTop = FBAHeap.peek(
            am,
            bidFallbackPrice,
            false
        );
        console.log(ordTop.amount, ordTop.price, ordTop.clientId);
        console.log(ord2.amount, ord2.price, ord2.clientId);
        assertEq(ordTop.price, ord2.price);
    }
}
