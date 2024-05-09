// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "suave-std/Test.sol";
import "suave-std/suavelib/Suave.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {FBA} from "../src/FBA.sol";
import {FBAHeap} from "../src/FBAHeap.sol";

contract TestForge is Test, SuaveEnabled {
    bool ISBUY = true;
    bool ISSELL = false;

    struct Fill {
        uint256 price;
        uint256 amount;
    }

    event FillEvent(Fill);
    event OrderPlace(uint256 price, uint256 amount, bool side);
    event OrderCancel(string orderId, bool side);

    function testPlaceOrder() public {
        // Test should:
        // Confirm a buy order is successfully placed by looking for emitted event
        FBA fba = new FBA();
        address(fba).call(fba.initFBA());

        FBAHeap.Order memory ord = FBAHeap.Order(100, 123, ISBUY, "order1");

        bytes memory o = fba.placeOrder(ord);
        vm.expectEmit(true, true, true, true);
        emit OrderPlace(ord.price, ord.amount, ord.side);
        address(fba).call(o);
    }

    function testCancelOrder() public {
        // Test should:
        // Confirm a cancel order is successfully processed by looking for emitted event
        FBA fba = new FBA();
        address(fba).call(fba.initFBA());

        string memory orderId = "order1";
        FBAHeap.Order memory ord = FBAHeap.Order(100, 123, ISSELL, orderId);
        address(fba).call(fba.placeOrder(ord));

        // Now confirm cancel works
        bytes memory o = fba.cancelOrder(orderId, ISSELL);
        vm.expectEmit(true, true, true, true);
        emit OrderCancel(orderId, ISSELL);
        address(fba).call(o);
    }

    function testMatchOrdersAtSamePriceCase1() public {
        FBA fba = new FBA();
        address(fba).call(fba.initFBA());

        uint256 tradePrice = 100;
        uint256 tradeAmount = 120;
        FBAHeap.Order memory ordBuy = FBAHeap.Order(tradePrice, tradeAmount, ISBUY, "order1");
        address(fba).call(fba.placeOrder(ordBuy));

        FBAHeap.Order memory ordSell = FBAHeap.Order(tradePrice, tradeAmount, ISSELL, "order2");
        address(fba).call(fba.placeOrder(ordSell));

        bytes memory o = fba.executeFills();
        Fill memory f = Fill(100, 120);
        vm.expectEmit(true, true, true, true);
        emit FillEvent(f);
        address(fba).call(o);
    }

    function testMatchOrdersAtSamePriceCase2() public {
        FBA fba = new FBA();
        address(fba).call(fba.initFBA());

        uint256 tradePrice = 100;
        FBAHeap.Order memory ordBuy = FBAHeap.Order(tradePrice, 100, ISBUY, "order1");
        address(fba).call(fba.placeOrder(ordBuy));

        FBAHeap.Order memory ordSell = FBAHeap.Order(tradePrice, 80, ISSELL, "order2");
        address(fba).call(fba.placeOrder(ordSell));

        bytes memory o = fba.executeFills();
        Fill memory f = Fill(100, 80);
        vm.expectEmit(true, true, true, true);
        emit FillEvent(f);
        address(fba).call(o);
    }

    function testMatchOrdersAtSamePriceCase3() public {
        FBA fba = new FBA();
        address(fba).call(fba.initFBA());

        uint256 tradePrice = 100;
        FBAHeap.Order memory ordBuy = FBAHeap.Order(tradePrice, 100, ISBUY, "order1");
        address(fba).call(fba.placeOrder(ordBuy));

        FBAHeap.Order memory ordSell1 = FBAHeap.Order(tradePrice, 90, ISSELL, "order2");
        FBAHeap.Order memory ordSell2 = FBAHeap.Order(tradePrice, 90, ISSELL, "order3");
        address(fba).call(fba.placeOrder(ordSell1));
        address(fba).call(fba.placeOrder(ordSell2));

        bytes memory o = fba.executeFills();
        Fill memory f = Fill(100, 100);
        vm.expectEmit(true, true, true, true);
        emit FillEvent(f);
        address(fba).call(o);
    }

    function testMatchOrdersAtSamePriceCase4() public {
        FBA fba = new FBA();
        address(fba).call(fba.initFBA());

        uint256 tradePrice = 100;
        FBAHeap.Order memory ordBuy1 = FBAHeap.Order(tradePrice, 90, ISBUY, "order1");
        FBAHeap.Order memory ordBuy2 = FBAHeap.Order(tradePrice, 90, ISBUY, "order2");
        address(fba).call(fba.placeOrder(ordBuy1));
        address(fba).call(fba.placeOrder(ordBuy2));

        FBAHeap.Order memory ordSell = FBAHeap.Order(tradePrice, 50000, ISSELL, "order3");
        address(fba).call(fba.placeOrder(ordSell));

        bytes memory o = fba.executeFills();
        Fill memory f = Fill(100, 180);
        vm.expectEmit(true, true, true, true);
        emit FillEvent(f);
        address(fba).call(o);
    }

    function testMatchOrdersAtSamePriceCase5() public {
        FBA fba = new FBA();
        address(fba).call(fba.initFBA());

        uint256 tradePrice = 100;
        for (uint256 i = 0; i < 100; i++) {
            FBAHeap.Order memory ordBuy = FBAHeap.Order(
                tradePrice,
                (i + 1), // total amount is 5050
                ISBUY,
                string.concat("order", Strings.toString(i + 1))
            );
            address(fba).call(fba.placeOrder(ordBuy));
        }

        FBAHeap.Order memory ordSell = FBAHeap.Order(tradePrice, 10000, ISSELL, "order101");
        address(fba).call(fba.placeOrder(ordSell));

        bytes memory o = fba.executeFills();
        Fill memory f = Fill(100, 5050);
        vm.expectEmit(true, true, true, true);
        emit FillEvent(f);
        address(fba).call(o);
    }

    function testMatchOrdersAtDifferentPriceCase1() public {
        FBA fba = new FBA();
        address(fba).call(fba.initFBA());

        FBAHeap.Order memory ordBuy = FBAHeap.Order(101, 100, ISBUY, "order1");
        address(fba).call(fba.placeOrder(ordBuy));

        FBAHeap.Order memory ordSell = FBAHeap.Order(99, 80, ISSELL, "order2");
        address(fba).call(fba.placeOrder(ordSell));

        bytes memory o = fba.executeFills();
        Fill memory f = Fill(100, 80);
        vm.expectEmit(true, true, true, true);
        emit FillEvent(f);
        address(fba).call(o);
    }

    function testMatchOrdersAtSameAndDifferentPriceCase1() public {
        FBA fba = new FBA();
        address(fba).call(fba.initFBA());

        FBAHeap.Order memory ordBuy1 = FBAHeap.Order(95, 100, ISBUY, "order1");
        FBAHeap.Order memory ordBuy2 = FBAHeap.Order(120, 100, ISBUY, "order2");
        address(fba).call(fba.placeOrder(ordBuy1));
        address(fba).call(fba.placeOrder(ordBuy2));

        FBAHeap.Order memory ordSell1 = FBAHeap.Order(95, 100, ISSELL, "order3");
        FBAHeap.Order memory ordSell2 = FBAHeap.Order(90, 100, ISSELL, "order4");
        address(fba).call(fba.placeOrder(ordSell1));
        address(fba).call(fba.placeOrder(ordSell2));

        bytes memory o = fba.executeFills();
        Fill memory f1 = Fill(95, 100);
        vm.expectEmit(true, true, true, true);
        emit FillEvent(f1);
        Fill memory f2 = Fill(105, 100);
        vm.expectEmit(true, true, true, true);
        emit FillEvent(f2);
        address(fba).call(o);
    }

    function testMatchOrdersWithCancelCase1() public {
        FBA fba = new FBA();
        address(fba).call(fba.initFBA());

        uint256 tradePrice = 100;
        FBAHeap.Order memory ordBuy1 = FBAHeap.Order(tradePrice, 20, ISBUY, "order1");
        FBAHeap.Order memory ordBuy2 = FBAHeap.Order(tradePrice, 50, ISBUY, "order2");
        address(fba).call(fba.placeOrder(ordBuy1));
        address(fba).call(fba.placeOrder(ordBuy2));
        FBAHeap.Order memory ordSell = FBAHeap.Order(tradePrice, 80, ISSELL, "order3");
        address(fba).call(fba.placeOrder(ordSell));

        address(fba).call(fba.cancelOrder(ordBuy2.orderId, ISBUY));

        bytes memory o = fba.executeFills();
        // if order isn't cancelled, this should be `Fill(100, 70)`
        Fill memory f = Fill(100, 20);
        vm.expectEmit(true, true, true, true);
        emit FillEvent(f);
        address(fba).call(o);
    }

    function testMatchOrdersWithCancelCase2() public {
        FBA fba = new FBA();
        address(fba).call(fba.initFBA());

        uint256 tradePrice = 100;
        for (uint256 i = 0; i < 100; i++) {
            FBAHeap.Order memory ordBuy = FBAHeap.Order(
                tradePrice,
                (i + 1), // total amount is 5050
                ISBUY,
                string.concat("order", Strings.toString(i + 1))
            );
            address(fba).call(fba.placeOrder(ordBuy));
        }

        for (uint256 i = 0; i < 50; i++) {
            address(fba).call(fba.cancelOrder(string.concat("order", Strings.toString(i + 1)), ISBUY)); // cancel total amount is 1275
        }

        FBAHeap.Order memory ordSell = FBAHeap.Order(tradePrice, 10000, ISSELL, "order1001");
        address(fba).call(fba.placeOrder(ordSell));

        bytes memory o = fba.executeFills();
        // if order isn't cancelled, this should be `Fill(100, 5050)`
        Fill memory f = Fill(100, 3775); // 5050 - 1275
        vm.expectEmit(true, true, true, true);
        emit FillEvent(f);
        address(fba).call(o);
    }

    function testMatchOrdersTwoTimes() public {
        FBA fba = new FBA();
        address(fba).call(fba.initFBA());

        // First batch auction
        uint256 firstTradePrice = 100;
        uint256 secondTradePrice = 95;
        for (uint256 i = 0; i < 100; i++) {
            FBAHeap.Order memory ordBuy = FBAHeap.Order(
                firstTradePrice,
                (i + 1), // total amount is 5050
                ISBUY,
                string.concat("order", Strings.toString(i + 10001))
            );
            address(fba).call(fba.placeOrder(ordBuy));
        }
        FBAHeap.Order memory ordBuyRemain = FBAHeap.Order(secondTradePrice, 100, ISBUY, "order10101");
        address(fba).call(fba.placeOrder(ordBuyRemain));

        for (uint256 i = 0; i < 50; i++) {
            address(fba).call(fba.cancelOrder(string.concat("order", Strings.toString(i + 10001)), ISBUY)); // cancel total amount is 1275
        }

        FBAHeap.Order memory ordSell = FBAHeap.Order(firstTradePrice, 10000, ISSELL, "order11001");
        address(fba).call(fba.placeOrder(ordSell));

        bytes memory o1 = fba.executeFills();
        // if order isn't cancelled, this should be `Fill(100, 5050)`
        Fill memory f1 = Fill(100, 3775); // 5050 - 1275
        vm.expectEmit(true, true, true, true);
        emit FillEvent(f1);
        address(fba).call(o1);

        // Second batch auction
        for (uint256 i = 0; i < 100; i++) {
            FBAHeap.Order memory ordSell2 =
                FBAHeap.Order(secondTradePrice, 50, ISSELL, string.concat("order", Strings.toString(i + 20001)));
            address(fba).call(fba.placeOrder(ordSell2));
        }
        // remove 99 orders
        for (uint256 i = 0; i < 99; i++) {
            address(fba).call(fba.cancelOrder(string.concat("order", Strings.toString(i + 20001)), ISSELL)); // cancel total amount is 1275
        }

        bytes memory o2 = fba.executeFills();
        // if order isn't cancelled, this should be `Fill(95, 100)`
        Fill memory f2 = Fill(95, 50);
        vm.expectEmit(true, true, true, true);
        emit FillEvent(f2);
        address(fba).call(o2);
    }

    function testMatchOrders100Times() public {
        FBA fba = new FBA();
        address(fba).call(fba.initFBA());

        for (uint256 i = 0; i < 100; i++) {
            executeOneBatch(fba, i);
        }
    }

    //////////// Internal methods

    function executeOneBatch(FBA fba, uint256 time) public {
        uint256 tradePrice = 100;
        FBAHeap.Order memory ordBuy1 =
            FBAHeap.Order(tradePrice, 20, ISBUY, string.concat("order", Strings.toString(time * 10000 + 1)));
        FBAHeap.Order memory ordBuy2 =
            FBAHeap.Order(tradePrice, 50, ISBUY, string.concat("order", Strings.toString(time * 10000 + 2)));
        address(fba).call(fba.placeOrder(ordBuy1));
        address(fba).call(fba.placeOrder(ordBuy2));
        FBAHeap.Order memory ordSell =
            FBAHeap.Order(tradePrice, 80, ISSELL, string.concat("order", Strings.toString(time * 10000 + 3)));
        address(fba).call(fba.placeOrder(ordSell));

        address(fba).call(fba.cancelOrder(ordBuy2.orderId, ISBUY));

        bytes memory o = fba.executeFills();
        // if order isn't cancelled, this should be `Fill(100, 70)`
        Fill memory f = Fill(100, 20);
        vm.expectEmit(true, true, true, true);
        emit FillEvent(f);
        address(fba).call(o);
    }
}
