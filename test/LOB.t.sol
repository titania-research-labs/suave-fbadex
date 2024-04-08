// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "suave-std/Test.sol";
import "suave-std/suavelib/Suave.sol";
import "forge-std/console.sol";
import {LOB} from "../src/LOB.sol";
import {LOBHeap} from "../src/LOBHeap.sol";

contract TestForge is Test, SuaveEnabled {
    function testInsertOrder() public {
        // Initializing library
        // No contract, just test library functionality
        address[] memory addressList;
        addressList = new address[](1);
        addressList[0] = 0xC8df3686b4Afb2BB53e60EAe97EF043FE03Fb829;

        LOB d = new LOB();
        bytes memory o1 = d.initLOB();
        address(d).call(o1);

        bool buy = true;
        bool sell = false;
        LOBHeap.LOBOrder memory ord = LOBHeap.LOBOrder(100, buy, 123, "abcd");
        LOBHeap.LOBOrder memory ord2 = LOBHeap.LOBOrder(101, sell, 123, "efgh");
        d.placeOrder(ord);
        d.placeOrder(ord2);
    }
}
