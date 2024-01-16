// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./Curves.sol";
import "./Security.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FeeSplitter is Security {
    Curves public curves;
    uint256 constant PRECISION = 1e18;

    // Custom errors
    error NoFeesToClaim();
    error NoTokenHolders();

    struct TokenData {
        uint256 cumulativeFeePerToken;
        mapping(address => uint256) userFeeOffset; // user => offSet // the number of fees alredy taken!!!! vaffanculo
        mapping(address => uint256) unclaimedFees; // user => unclaimedFees
    }

    struct UserClaimData {
        uint256 claimableFees;
        address token;
    }

    mapping(address => TokenData) public tokensData; // subject => TokenData
    mapping(address => address[]) public userTokens; // user => subjects[]

    event FeesClaimed(address indexed token, address indexed user, uint256 amount);

    constructor() Security() {}

    function setCurves(Curves curves_) public {//@audit no access control
        curves = curves_;
    }

    function balanceOf(address token, address account) public view returns (uint256) {//amount * PRECISION
        return curves.curvesTokenBalance(token, account) * PRECISION; // ok  * 1e18
    }

    function totalSupply(address token) public view returns (uint256) { // supply * PRECISION // all internal supply (supply - external erc20)
        //@dev: this is the amount of tokens that are not locked in the contract. The locked tokens are in the ERC20 contract
        return (curves.curvesTokenSupply(token) - curves.curvesTokenBalance(token, address(curves))) * PRECISION;
    }

    function getUserTokens(address user) public view returns (address[] memory) {// user => subjects[]
        return userTokens[user];
    }

    function getUserTokensAndClaimable(address user) public view returns (UserClaimData[] memory) {//user => claiAndToken[](fees , subject )
        address[] memory tokens = getUserTokens(user); //subjects[]
        UserClaimData[] memory result = new UserClaimData[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 claimable = getClaimableFees(token, user);
            result[i] = UserClaimData(claimable, token);
        }
        return result;
    }

    function updateFeeCredit(address token, address account) internal {// subject , user
        TokenData storage data = tokensData[token]; // token => {cumulativeFee, (user => offSet) , (user => unclaimedFees)}
        uint256 balance = balanceOf(token, account); // user amount *1e18 
        if (balance > 0) { // if is a holder
            uint256 owed = (data.cumulativeFeePerToken - data.userFeeOffset[account]) * balance; // (feesPerToken - offset )*balance 
            data.unclaimedFees[account] += owed / PRECISION; // = 
            data.userFeeOffset[account] = data.cumulativeFeePerToken;
        }
    }

    function getClaimableFees(address token, address account) public view returns (uint256) { 
        TokenData storage data = tokensData[token];
        uint256 balance = balanceOf(token, account);
        uint256 owed = (data.cumulativeFeePerToken - data.userFeeOffset[account]) * balance;
        return (owed / PRECISION) + data.unclaimedFees[account];
    }

    function claimFees(address token) external { 
        updateFeeCredit(token, msg.sender); // update unclaimedFees
        uint256 claimable = getClaimableFees(token, msg.sender); // ok
        if (claimable == 0) revert NoFeesToClaim(); // ok
        tokensData[token].unclaimedFees[msg.sender] = 0; // reset fees 
        payable(msg.sender).transfer(claimable); // pay user
        emit FeesClaimed(token, msg.sender, claimable); //emit
    }

    function addFees(address token) public payable onlyManager {// add just update cumulativeFeePerToken
        uint256 totalSupply_ = totalSupply(token);
        if (totalSupply_ == 0) revert NoTokenHolders(); // if no holder => revert
        TokenData storage data = tokensData[token];
        data.cumulativeFeePerToken += (msg.value * PRECISION) / totalSupply_; //cumulativeFeePerToken += value / supply
    }

    function onBalanceChange(address token, address account) public onlyManager {
        TokenData storage data = tokensData[token]; // tokensData {cumulativeFees,(user=>offSet),(user=>unclaimedFees)}
        data.userFeeOffset[account] = data.cumulativeFeePerToken; // userOffset = cumulativeFeePerToken 
        if (balanceOf(token, account) > 0) userTokens[account].push(token); //if user is a holder =>  user=> subjects[].push(subject)
    }

    //@dev: this may fail if the the list is long. Get first the list with getUserTokens to estimate and prepare the batch
    function batchClaiming(address[] calldata tokenList) external { // claim all your fess of all your tokens
        uint256 totalClaimable = 0;
        for (uint256 i = 0; i < tokenList.length; i++) {
            address token = tokenList[i];
            updateFeeCredit(token, msg.sender);
            uint256 claimable = getClaimableFees(token, msg.sender);
            if (claimable > 0) {
                tokensData[token].unclaimedFees[msg.sender] = 0;
                totalClaimable += claimable;
                emit FeesClaimed(token, msg.sender, claimable);
            }
        }
        if (totalClaimable == 0) revert NoFeesToClaim();
        payable(msg.sender).transfer(totalClaimable);
    }

    receive() external payable {}
}

// alice 1  => totalSupply = 1e18 ; price 0
// - onBalanceChange()
// aliceOffset=  cumulativeFeePerToken = 0;
// - addFees()
// cumulativeFeePerToken = price * 1e18 / totalSupply = 0
// alice Claimable Fees = ((cumulativeFeePerToken - aliceOffset ) * balance )/ 1e18 + unclaimedFees = (0 - 0) * 1 + 0 = 0
// bob claimable fess   = (0 - 0) * 0 /1e18 + 0;
// total fees = 0


// bob 1 => totalSupply = 2e18; price = 100
// - onBalanceChange()
// bobUserFeeOffset =  cumulativeFeePerToken = 0;
// - addFees()
// cumulativeFeePerToken = price * 1e18 / 2e18 = 100 * 1/2 = 50
// alice claimable fees = (50 - 0) * 1e18/1e18 + 0 = 50
// bob claimable fess   = (50 - 0) * 1e18/1e18 + 0 = 50
// total fees = 100

// bob 1 totalSupply = 3e18 ; price = 150;
// - onBalanceChange()
// bobUserFeeOffset =  cumulativeFeePerToken = 50;
// - addFees()
// cumulativeFeePerToken += price * 1e18 / 3e18 = 150 * 1/3 = 50+ 50 =100
// alice claimable fees = (100 - 0) * 1e18/1e18 + 0 = 100
// bob claimable fess   = (100 - 50) * 2e18/1e18 + 0 = 100
// total fees = 250

