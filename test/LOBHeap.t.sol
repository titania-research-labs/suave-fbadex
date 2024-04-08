// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "suave-std/Test.sol";
import "suave-std/suavelib/Suave.sol";
import "forge-std/console.sol";
import {LOBHeap} from "../src/LOBHeap.sol";

contract TestForge is Test, SuaveEnabled {
    function testInsertOrder() public {
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
        LOBHeap.ArrayMetadata memory am = LOBHeap.ArrayMetadata(0, record1.id);
        LOBHeap.arrSetMetadata(am);
        // For the map
        Suave.DataRecord memory record2 = Suave.newDataRecord(
            0,
            addressList,
            addressList,
            "suaveLOB:v0:dataId"
        );
        LOBHeap.MapMetadata memory mm = LOBHeap.MapMetadata(record2.id);
        LOBHeap.mapSetMetadata(mm);

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
        LOBHeap.ArrayMetadata memory am = LOBHeap.ArrayMetadata(0, record1.id);
        LOBHeap.arrSetMetadata(am);
        // For the map
        Suave.DataRecord memory record2 = Suave.newDataRecord(
            0,
            addressList,
            addressList,
            "suaveLOB:v0:dataId"
        );
        LOBHeap.MapMetadata memory mm = LOBHeap.MapMetadata(record2.id);
        LOBHeap.mapSetMetadata(mm);

        LOBHeap.LOBOrder memory ord = LOBHeap.LOBOrder(100, true, 123, "abcd");
        LOBHeap.LOBOrder memory ord2 = LOBHeap.LOBOrder(101, true, 456, "efgh");

        LOBHeap.insertOrder(am, mm, ord);
        LOBHeap.insertOrder(am, mm, ord2);
        LOBHeap.deleteOrder(am, mm, ord.clientId);

        uint askFallbackPrice = type(uint).max;
        LOBHeap.LOBOrder memory ord3 = LOBHeap.peek(am, askFallbackPrice, true);
        console.log(ord3.amount, ord3.price, ord3.clientId);
    }
}
