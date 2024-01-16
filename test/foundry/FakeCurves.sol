// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {FeeSplitter} from "../../contracts/FeeSplitter.sol";

contract FakeCurves {
    function curvesTokenBalance(address token, address /* account */ ) public view returns (uint256) {
        FeeSplitter feeSplitter = FeeSplitter(payable(address(msg.sender)));
        (uint256 cumulativeFeePerToken) = feeSplitter.tokensData(token);
        uint256 feeSplitterBalance = address(msg.sender).balance;
        // formula in order to make FeeSplitter::getClaimableFees() return the balance of FeeSplitter contract
        // claimableFees = (cumulativeFeePerToken - userFeeOffset) * balance
        // claimableFees => feeSplitterBalance
        // x => balance
        // x = feeSplitterBalance  / (cumulativeFeePerToken - userFeeOffset);
        return feeSplitterBalance / (cumulativeFeePerToken - 0);
    }

    function curvesTokenSupply() public {}
}
