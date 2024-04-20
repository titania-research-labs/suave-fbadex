// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "suave-std/Test.sol";
import "suave-std/suavelib/Suave.sol";
import "forge-std/console.sol";
import {FBA} from "../src/FBA.sol";
import {FBAHeap} from "../src/FBAHeap.sol";

contract TestForge is Test, SuaveEnabled {
    bool ISBUY = true;
    bool ISSELL = false;

    struct Fill {
        uint amount;
        uint price;
    }
    event FillEvent(Fill);
    event OrderPlace(uint256 price, bool side, uint256 amount);
    event OrderCancel(uint256 price, bool side, uint256 amount);

    function testPlaceOrder() public {
        // Test should:
        // Confirm a buy order is successfully placed by looking for emitted event
        FBA fba = new FBA();
        bytes memory o1 = fba.initFBA();
        address(fba).call(o1);

        FBAHeap.FBAOrder memory ord = FBAHeap.FBAOrder(100, ISBUY, 123, "abcd");

        bytes memory o2 = fba.placeOrder(ord);
        vm.expectEmit(true, true, true, true);
        emit OrderPlace(ord.price, ord.side, ord.amount);
        address(fba).call(o2);
    }

    function testCancelOrder() public {
        // Test should:
        // Confirm a cancel order is successfully processed by looking for emitted event
        FBA fba = new FBA();
        bytes memory o1 = fba.initFBA();
        address(fba).call(o1);

        // Place logic - same as above but do a sell order
        string memory clientId = "abcd";

        FBAHeap.FBAOrder memory ord = FBAHeap.FBAOrder(
            100,
            ISSELL,
            123,
            clientId
        );
        bytes memory o2 = fba.placeOrder(ord);
        address(fba).call(o2);

        // Now confirm cancel works
        bytes memory o3 = fba.cancelOrder(clientId, ISSELL);
        vm.expectEmit(true, true, true, true);
        emit OrderCancel(ord.price, ord.side, ord.amount);
        address(fba).call(o3);
    }

    function testMatchOrder() public {
        FBA fba = new FBA();
        bytes memory o1 = fba.initFBA();
        address(fba).call(o1);

        uint tradePrice = 100;
        FBAHeap.FBAOrder memory ordBuy = FBAHeap.FBAOrder(
            tradePrice,
            ISBUY,
            100,
            "abcd"
        );
        bytes memory o2 = fba.placeOrder(ordBuy);
        address(fba).call(o2);

        FBAHeap.FBAOrder memory ordSell = FBAHeap.FBAOrder(
            tradePrice,
            ISSELL,
            80,
            "defg"
        );
        bytes memory o3 = fba.placeOrder(ordSell);
        // This should have resulted in a matching order of amount 80 at price 100
        Fill memory f = Fill(80, 100);
        vm.expectEmit(true, true, true, true);
        emit FillEvent(f);
        address(fba).call(o3);

        // TODO - should we confirm that there's still a sell order of 20 left?
    }
}
