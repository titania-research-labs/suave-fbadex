// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "suave-std/Test.sol";
import "suave-std/suavelib/Suave.sol";
import "forge-std/console.sol";
import {LOB} from "../src/LOB.sol";
import {LOBHeap} from "../src/LOBHeap.sol";

contract TestForge is Test, SuaveEnabled {
    event OrderPlace(uint256 price, bool side, uint256 amount);
    event OrderCancel(uint256 price, bool side, uint256 amount);

    function testPlaceOrder() public {
        // Test should:
        // Confirm a buy order is successfully placed by looking for emitted event
        LOB lob = new LOB();
        bytes memory o1 = lob.initLOB();
        address(lob).call(o1);

        bool buy = true;
        LOBHeap.LOBOrder memory ord = LOBHeap.LOBOrder(100, buy, 123, "abcd");

        bytes memory o2 = lob.placeOrder(ord);
        vm.expectEmit(true, true, true, true);
        emit OrderPlace(ord.price, ord.side, ord.amount);
        address(lob).call(o2);
    }

    function testCancelOrder() public {
        // Test should:
        // Confirm a cancel order is successfully processed by looking for emitted event
        LOB lob = new LOB();
        bytes memory o1 = lob.initLOB();
        address(lob).call(o1);

        // Place logic - same as above but do a sell order
        bool sell = false;
        string memory clientId = "abcd";

        LOBHeap.LOBOrder memory ord = LOBHeap.LOBOrder(
            100,
            sell,
            123,
            clientId
        );
        bytes memory o2 = lob.placeOrder(ord);
        address(lob).call(o2);

        // Now confirm cancel works
        bytes memory o3 = lob.cancelOrder(clientId, sell);
        vm.expectEmit(true, true, true, true);
        emit OrderCancel(ord.price, ord.side, ord.amount);
        address(lob).call(o3);
    }
}
