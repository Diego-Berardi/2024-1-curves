// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.7;

contract Revert {
    receive() external payable {
        assert(false);
    }
}
