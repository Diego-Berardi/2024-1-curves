// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.7;

import {Curves} from "../../contracts/Curves.sol";
import {console} from "forge-std/Test.sol";

contract Attack {
    address owner;
    Curves curves;
    bool isOpen;

    constructor(Curves _curves) {
        owner = msg.sender;
        curves = _curves;
        isOpen = false;
    }

    function attackFunc() public payable {
        curves.buyCurvesToken(address(this), 1);
        // assertEq(curves.curvesTokenBalance(address(_alice), address(_alice)), 1);
        isOpen = true;
        uint256 price = curves.getBuyPrice(address(this), 2);
        curves.buyCurvesToken{value: price}(address(this), 2);
        // assertEq(curves.curvesTokenBalance(address(_alice), address(_alice)), 3);

        // curves.sellCurvesToken(address(this), 2);
        isOpen = false;
    }

    receive() external payable {
        if (isOpen) {
            
            console.log("hello", isOpen);

        }
    }
}
