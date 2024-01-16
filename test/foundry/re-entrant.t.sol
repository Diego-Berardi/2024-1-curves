// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.7;

import {Test, console} from "forge-std/Test.sol";

import {CurvesERC20Factory} from "../../contracts/CurvesERC20Factory.sol";
import {FeeSplitter} from "../../contracts/FeeSplitter.sol";
import {Curves, CurvesErrors} from "../../contracts/Curves.sol";

import {Attack} from "./Attack.sol";

contract CurvesTest is Test {
    CurvesERC20Factory curveERC20Factory;
    FeeSplitter feeSplitter;
    Curves curves;

    address owner = makeAddr("owner");
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
        // vm.stopPrank();

        //set fees

        curves.setMaxFeePercent(50);
        curves.setProtocolFeePercent(5, address(owner));
        curves.setExternalFeePercent(5, 0, 0);
        vm.stopPrank();
    }

    function test_feeEconomics() public {
        (
            address protocolFeeDestination,
            uint256 protocolFeePercent,
            uint256 subjectFeePercent,
            uint256 referralFeePercent,
            uint256 holdersFeePercent,
            uint256 maxFeePercent
        ) = curves.feesEconomics();

        console.log("protocolFeeDestination:", protocolFeeDestination);
        console.log("protocolFeePercent:", protocolFeePercent);
        console.log("subjectFeePercent: ", subjectFeePercent);
        console.log("referralFeePercent:", referralFeePercent);
        console.log("holdersFeePercent: ", holdersFeePercent);
        console.log("----maxFeePercent: ", maxFeePercent);

        uint256 price = curves.getPrice(2, 3);
        console.log(price);
        (,,,, uint256 totalFee) = curves.getFees(price);

        console.log(totalFee);
    }

    function test_reEntrancy() public {
        vm.deal(alice, 1 ether);

        vm.startPrank(alice);

        Attack attackContract = new Attack(curves);

        attackContract.attackFunc{value: 1 ether}();

        vm.stopPrank();
    }

    function test_prova() public {
        uint256 price = (curves.getPrice(1, 0));
        console.log("price:", price);
        (uint256 protocolFee, uint256 subjectFee, uint256 referralFee, uint256 holdersFee, uint256 totalFee) =
            curves.getFees(price);
        console.log("totalfees" ,totalFee);
    }
}
