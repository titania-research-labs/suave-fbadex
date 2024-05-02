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
        uint256 amount;
        uint256 price;
    }

    event FillEvent(Fill);
    event OrderPlace(uint256 price, bool side, uint256 amount);
    event OrderCancel(string clientId, bool side);

    function testPlaceOrder() public {
        // Test should:
        // Confirm a buy order is successfully placed by looking for emitted event
        FBA fba = new FBA();
        address(fba).call(fba.initFBA());

        FBAHeap.FBAOrder memory ord = FBAHeap.FBAOrder(100, ISBUY, 123, "abcd");

        bytes memory o = fba.placeOrder(ord);
        vm.expectEmit(true, true, true, true);
        emit OrderPlace(ord.price, ord.side, ord.amount);
        address(fba).call(o);
    }

    function testCancelOrder() public {
        // Test should:
        // Confirm a cancel order is successfully processed by looking for emitted event
        FBA fba = new FBA();
        address(fba).call(fba.initFBA());

        string memory clientId = "abcd";
        FBAHeap.FBAOrder memory ord = FBAHeap.FBAOrder(100, ISSELL, 123, clientId);
        address(fba).call(fba.placeOrder(ord));

        // Now confirm cancel works
        bytes memory o = fba.cancelOrder(clientId, ISSELL);
        vm.expectEmit(true, true, true, true);
        emit OrderCancel(clientId, ISSELL);
        address(fba).call(o);
    }

    function testMatchOrderBuy1Sell1() public {
        FBA fba = new FBA();
        address(fba).call(fba.initFBA());

        uint256 tradePrice = 100;
        FBAHeap.FBAOrder memory ordBuy = FBAHeap.FBAOrder(tradePrice, ISBUY, 100, "abcd");
        address(fba).call(fba.placeOrder(ordBuy));

        FBAHeap.FBAOrder memory ordSell = FBAHeap.FBAOrder(tradePrice, ISSELL, 80, "efgh");
        address(fba).call(fba.placeOrder(ordSell));

        bytes memory o = fba.executeFills();
        // This should have resulted in a matching order of amount 80 at price 100
        Fill memory f = Fill(80, 100);
        vm.expectEmit(true, true, true, true);
        emit FillEvent(f);
        address(fba).call(o);
    }

    // // TODO: this test is failing because of arithmetic overflow or underflow
    // function testMatchOrderBuy1Sell2() public {
    //     FBA fba = new FBA();
    //     address(fba).call(fba.initFBA());

    //     uint tradePrice = 100;
    //     FBAHeap.FBAOrder memory ordBuy = FBAHeap.FBAOrder(
    //         tradePrice,
    //         ISBUY,
    //         100,
    //         "abcd"
    //     );
    //     address(fba).call(fba.placeOrder(ordBuy));

    //     FBAHeap.FBAOrder memory ordSell1 = FBAHeap.FBAOrder(
    //         tradePrice,
    //         ISSELL,
    //         80,
    //         "defg"
    //     );
    //     address(fba).call(fba.placeOrder(ordSell1));
    //     FBAHeap.FBAOrder memory ordSell2 = FBAHeap.FBAOrder(
    //         tradePrice,
    //         ISSELL,
    //         60,
    //         "defg"
    //     );
    //     address(fba).call(fba.placeOrder(ordSell2));

    //     bytes memory o = fba.executeFills();
    //     // This should have resulted in a matching order of amount 80 at price 100
    //     Fill memory f = Fill(80, 100);
    //     vm.expectEmit(true, true, true, true);
    //     emit FillEvent(f);
    //     address(fba).call(o);
    // }

    function testCancelOrderBuy2Sell1BuyCancel1() public {
        FBA fba = new FBA();
        address(fba).call(fba.initFBA());

        uint256 tradePrice = 100;
        string memory clientId = "abcd";
        FBAHeap.FBAOrder memory ordBuy = FBAHeap.FBAOrder(tradePrice, ISBUY, 100, clientId);
        address(fba).call(fba.placeOrder(ordBuy));
        address(fba).call(fba.placeOrder(ordBuy));
        FBAHeap.FBAOrder memory ordSell = FBAHeap.FBAOrder(tradePrice, ISSELL, 80, "efgh");
        address(fba).call(fba.placeOrder(ordSell));

        address(fba).call(fba.cancelOrder(clientId, ISBUY));

        bytes memory o = fba.executeFills();
        // This should have resulted in a matching order of amount 80 at price 100
        Fill memory f = Fill(80, 100);
        vm.expectEmit(true, true, true, true);
        emit FillEvent(f);
        address(fba).call(o);
    }
}
