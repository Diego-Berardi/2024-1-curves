// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.7;

import {Test, console} from "forge-std/Test.sol";

import {CurvesERC20Factory} from "../../contracts/CurvesERC20Factory.sol";
import {FeeSplitter} from "../../contracts/FeeSplitter.sol";
import {Curves, CurvesErrors} from "../../contracts/Curves.sol";
import {CurvesERC20} from "../../contracts/CurvesERC20.sol";

contract CurvesTest is Test {
    CurvesERC20Factory curveERC20Factory;
    FeeSplitter feeSplitter;
    Curves curves;

    address owner = makeAddr("owner");
    address feeReceiverOwner = makeAddr("feeReceiverOwner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address hacker = makeAddr("hacker");
    address victim = makeAddr("victim");

    uint256 constant FRIEND_TECH_INITIAL_PRICE = 62_500_000_000_000;

    function setUp() public {
        vm.deal(owner, 99 ether);

        vm.startPrank(owner);
        curveERC20Factory = new CurvesERC20Factory();
        feeSplitter = new FeeSplitter();
        curves = new Curves(address(curveERC20Factory), address(feeSplitter));
        feeSplitter.setCurves((curves));
        feeSplitter.setManager(address(curves), true);
        vm.stopPrank();
    }

    function test_buy1() public {
        vm.deal(alice, 3 ether);
        console.log(curves.getBuyPrice(alice, 1));

        vm.startPrank(alice);
        curves.buyCurvesToken(address(alice), 1);

        // assertEq(curves.curvesTokenBalance(address(alice), address(alice)), 1);
        console.log("cv alice balance :", curves.curvesTokenBalance(address(alice), address(alice)));
        console.log("alice eth balance:", alice.balance);

        console.log(curves.getBuyPrice(alice, 1));
        console.log(FRIEND_TECH_INITIAL_PRICE);

        curves.buyCurvesToken{value: FRIEND_TECH_INITIAL_PRICE}(address(alice), 1);
        console.log("cv alice balance :", curves.curvesTokenBalance(address(alice), address(alice)));
        console.log("alice eth balance:", alice.balance);

        console.log(curves.getBuyPrice(alice, 1));
    }


    function test_dosBug() public {
        // vm.deal(victim, 15 ether);

        vm.prank(charlie);
        curves.buyCurvesToken(charlie, 1);
        assertEq(curves.curvesTokenBalance(address(charlie), address(charlie)), 1);

        vm.startPrank(victim);
        uint256 price = curves.getBuyPrice(charlie, 1);
        curves.buyCurvesToken{value: price}(address(charlie), 1);
        assertEq(curves.curvesTokenBalance(address(charlie), address(victim)), 1);
        //227683
        //458533
        //2767033
        //25852033
    }

    function test_selling() public {
        vm.deal(alice, 1 ether);

        vm.startPrank(alice);
        curves.buyCurvesToken(address(alice), 1);
        assertEq(curves.curvesTokenBalance(address(alice), address(alice)), 1);
        uint256 price = curves.getBuyPrice(alice, 2);
        curves.buyCurvesToken{value: price}(address(alice), 2);
        assertEq(curves.curvesTokenBalance(address(alice), address(alice)), 3);
        vm.stopPrank();

        vm.deal(bob, 1 ether);
        vm.startPrank(bob);
        price = curves.getBuyPrice(alice, 3);
        curves.buyCurvesToken{value: price}(address(alice), 3);
        assertEq(curves.curvesTokenBalance(address(alice), address(bob)), 3);

        vm.expectRevert(CurvesErrors.InsufficientBalance.selector);
        curves.sellCurvesToken(address(alice), 4);
    }

    // function test_math() public  {
    //     console.log("price", curves.getPrice(1, 1000));
    //     // console.log(curves.getPrice(0));
    //     //10000=> 20_836_458:437_500_000_000_000_000
    //     //100000=> 20_833_645_834:375_000_000_000_000_000
    // }

    // function test_fuzzMath(uint256 supply, uint256 amount) public {
    //     supply = bound(supply, 0, 1e20);
    //     amount = bound(amount, 0, 1e20);
    //     if (supply == 0) {
    //         amount = 1;
    //     }
    //     curves.getPrice(supply, amount);
    // }

    // function test_consoleFeeEconomics() public {
    //     (
    //         address protocolFeeDestination,
    //         uint256 protocolFeePercent,
    //         uint256 subjectFeePercent,
    //         uint256 referralFeePercent,
    //         uint256 holdersFeePercent,
    //         uint256 maxFeePercent
    //     ) = curves.feesEconomics();

    //     console.log(protocolFeeDestination);
    //     console.log(protocolFeePercent);
    //     console.log(subjectFeePercent);
    //     console.log(referralFeePercent);
    //     console.log(holdersFeePercent);
    //     console.log(maxFeePercent);

    //     uint256 price = curves.getPrice(2, 3);
    //     console.log(price);
    //     (,,,, uint256 totalFee) = curves.getFees(price);

    //     console.log(totalFee);
    // }

    function test_withdraw() public {
        setFees();
        vm.deal(alice, 1 ether);

        vm.startPrank(alice);
        curves.buyCurvesToken(alice, 1);
        assertEq(curves.curvesTokenBalance(alice, alice), 1);
        uint256 price = curves.getBuyPrice(alice, 2);
        curves.buyCurvesToken{value: price}(alice, 2);
        assertEq(curves.curvesTokenBalance(alice, alice), 3);

        assertEq(curves.curvesTokenBalance(alice, address(curves)), 0);
        curves.withdraw(alice, 2);
        assertEq(curves.curvesTokenBalance(alice, address(curves)), 2);
        assertEq(curves.curvesTokenBalance(alice, alice), 1);

        (string memory name, string memory symbol, address externalTokenAddress) = (curves.externalCurvesTokens(alice));

        CurvesERC20 curvesERC20 = CurvesERC20(externalTokenAddress);
        assertEq(curvesERC20.name(), name);
        assertEq(curvesERC20.symbol(), symbol);
        assertEq(curvesERC20.owner(), address(curves));
        assertEq(curvesERC20.balanceOf(alice), 2 ether);

        curvesERC20.transfer(bob, 2 ether);
        assertEq(curvesERC20.balanceOf(bob), 2 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        curves.deposit(alice, 2 ether);
        assertEq(curvesERC20.balanceOf(bob), 0);
        assertEq(curves.curvesTokenBalance(alice, bob), 2);
        uint256 sellPrice = curves.getSellPrice(alice, 2);
        (,,,, uint256 totalFee) = curves.getFees(sellPrice);
        console.log(sellPrice, totalFee);
        curves.sellCurvesToken(alice, 2);
        assertEq(curves.curvesTokenBalance(alice, bob), 0);

        console.log(alice.balance);
        console.log(bob.balance);
        console.log(alice.balance + bob.balance);
        console.log(feeReceiverOwner.balance);
    }

    //helper function-----------------------
    function setFees() public {
        // 50/1000 => 5%
        //   50_000_000_000000000
        //1_000_000_000_000000000
        vm.startPrank(owner);
        curves.setMaxFeePercent(50_000_000_000000000 + 50_000_000_000000000);
        curves.setProtocolFeePercent(50_000_000_000000000, address(feeReceiverOwner)); //0.05 => 5%
        curves.setExternalFeePercent(50_000_000_000000000, 0, 0);

        vm.stopPrank();
    }

    function test_handleFees() public {
        setFees();
        // vm.deal(alice, 1 ether);

        vm.startPrank(alice);
        curves.buyCurvesToken(alice, 1);
        assertEq(curves.curvesTokenBalance(alice, alice), 1);
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 price = curves.getBuyPrice(alice, 2);
        (,,,, uint256 totalFee) = curves.getFees(price);
        console.log("buy price:", price);
        console.log("buy price/1ether:", price / 1 ether);
        console.log("total fee:", totalFee);

        uint256 amount = price + totalFee;
        vm.deal(bob, amount);
        curves.buyCurvesToken{value: amount}(alice, 2);
        assertEq(curves.curvesTokenBalance(alice, bob), 2);

        curves.sellCurvesToken(alice, 2);
        console.log("bob balance", bob.balance);
        console.log(amount - bob.balance);

        console.log("feeReceiverOwner bal:", feeReceiverOwner.balance);
        console.log("alice balance ------:", alice.balance);
    }

    function test_buyTokenWithName() public {
        vm.startPrank(alice);

        curves.buyCurvesTokenWithName(alice, 1, "gigi", "GIGI");
        assertEq(curves.curvesTokenBalance(alice, alice), 1);
        assertEq(curves.symbolToSubject("GIGI"), alice);

        (string memory name, string memory symbol, address externalTokenAddress) = (curves.externalCurvesTokens(alice));

        CurvesERC20 curvesERC20 = CurvesERC20(externalTokenAddress);
        assertEq(curvesERC20.name(), name);
        assertEq(curvesERC20.symbol(), symbol);
        assertEq(curvesERC20.owner(), address(curves));
        assertEq(curvesERC20.totalSupply(), 0);

        // curves.buyCurvesTokenWithName(alice, 1, "pino", "pino");
    }
}
