// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import "./CurvesERC20.sol";
import "./CurvesERC20Factory.sol";

import "./FeeSplitter.sol";
import "./Security.sol";

interface CurvesErrors {
    // Access-related
    error UnauthorizedCurvesTokenSubject();
    // Balance-related
    error InsufficientPayment();
    error CannotSendFunds();
    error InsufficientBalance();
    // ERC20-related
    error InvalidERC20Metadata();
    error ERC20TokenAlreadyMinted();
    // State-related
    error TokenAbsentForCurvesTokenSubject();
    error CurveAlreadyExists();
    // Transaction-related
    error LastTokenCannotBeSold();
    error ContractCannotReceiveTransfer();
    error ExceededMaxBuyAmount();
    error NonIntegerDepositAmount();
    // Proof-related
    error UnverifiedProof();
    // Presale-related
    error PresaleUnavailable();
    error InvalidPresaleStartTime();
    error SaleNotOpen();
    // Fee related
    error InvalidFeeDefinition();
}

contract Curves is CurvesErrors, Security {
    address public curvesERC20Factory;
    FeeSplitter public feeRedistributor;
    string public constant DEFAULT_NAME = "Curves";
    string public constant DEFAULT_SYMBOL = "CURVES";
    // Counter for CURVES tokens minted
    uint256 private _curvesTokenCounter = 0;

    struct ExternalTokenMeta {
        string name;
        string symbol;
        address token;
    }

    struct PresaleMeta {
        uint256 startTime;
        bytes32 merkleRoot;
        uint256 maxBuy;
    }

    mapping(address => ExternalTokenMeta) public externalCurvesTokens; // subject => erc20(name, symbol, addr)
    mapping(address => address) public externalCurvesToSubject; // addr(erc20) => subject
    mapping(string => address) public symbolToSubject; // symbol => subject

    mapping(address => PresaleMeta) public presalesMeta; // subject => (startTime, merkleRoot, maxBuy)
    mapping(address => mapping(address => uint256)) public presalesBuys; // subject => (user => amountBought)

    struct FeesEconomics {
        address protocolFeeDestination;
        uint256 protocolFeePercent;
        uint256 subjectFeePercent;
        uint256 referralFeePercent;
        uint256 holdersFeePercent;
        uint256 maxFeePercent;
    }

    FeesEconomics public feesEconomics;
    mapping(address => address) public referralFeeDestination;

    event Trade(
        address trader,
        address subject,
        bool isBuy,
        uint256 tokenAmount,
        uint256 ethAmount,
        uint256 protocolEthAmount,
        uint256 subjectEthAmount,
        uint256 supply
    );

    event Transfer(address indexed curvesTokenSubject, address indexed from, address indexed to, uint256 value);
    event WhitelistUpdated(address indexed presale, bytes32 indexed root);
    event TokenDeployed(address indexed curvesTokenSubject, address indexed erc20token, string name, string symbol);

    // TokenSubject => (Holder => Balance)
    mapping(address => mapping(address => uint256)) public curvesTokenBalance;

    // TokenSubject => Supply
    mapping(address => uint256) public curvesTokenSupply;
    // user => tokenSubjects
    mapping(address => address[]) private ownedCurvesTokenSubjects;

    mapping(address => uint256) private addressToUnclaimedFees;

    modifier onlyTokenSubject(address curvesTokenSubject) {
        // ok
        if (curvesTokenSubject != msg.sender) revert UnauthorizedCurvesTokenSubject();
        _;
    }

    constructor(address curvesERC20Factory_, address feeRedistributor_) Security() {
        //ok
        curvesERC20Factory = curvesERC20Factory_;
        feeRedistributor = FeeSplitter(payable(feeRedistributor_));
    }

    function setFeeRedistributor(address feeRedistributor_) external onlyOwner {
        //ok
        feeRedistributor = FeeSplitter(payable(feeRedistributor_));
    }

    function setMaxFeePercent(uint256 maxFeePercent_) external onlyManager {
        //ok
        if (
            feesEconomics.protocolFeePercent + feesEconomics.subjectFeePercent + feesEconomics.referralFeePercent
                + feesEconomics.holdersFeePercent > maxFeePercent_
        ) revert InvalidFeeDefinition();
        feesEconomics.maxFeePercent = maxFeePercent_;
    }

    function setProtocolFeePercent(uint256 protocolFeePercent_, address protocolFeeDestination_) external onlyOwner {
        // ok
        if (
            protocolFeePercent_ + feesEconomics.subjectFeePercent + feesEconomics.referralFeePercent
                + feesEconomics.holdersFeePercent > feesEconomics.maxFeePercent || protocolFeeDestination_ == address(0)
        ) revert InvalidFeeDefinition();
        feesEconomics.protocolFeePercent = protocolFeePercent_;
        feesEconomics.protocolFeeDestination = protocolFeeDestination_;
    }

    function setExternalFeePercent( // set (subjectFeePercent,referralFeePercent,holdersFeePercent)
    uint256 subjectFeePercent_, uint256 referralFeePercent_, uint256 holdersFeePercent_)
        external
        onlyManager
    {
        if (
            feesEconomics.protocolFeePercent + subjectFeePercent_ + referralFeePercent_ + holdersFeePercent_
                > feesEconomics.maxFeePercent
        ) revert InvalidFeeDefinition(); //if sum > totalFee revert
        feesEconomics.subjectFeePercent = subjectFeePercent_;
        feesEconomics.referralFeePercent = referralFeePercent_;
        feesEconomics.holdersFeePercent = holdersFeePercent_;
    }

    function setReferralFeeDestination(address curvesTokenSubject, address referralFeeDestination_)
        public
        onlyTokenSubject(curvesTokenSubject)
    {
        //ok
        referralFeeDestination[curvesTokenSubject] = referralFeeDestination_;
    }

    function setERC20Factory(address factory_) external onlyOwner {
        //ok
        curvesERC20Factory = factory_;
    }

    function getFees( // price * fee%
    uint256 price)
        public
        view
        returns (uint256 protocolFee, uint256 subjectFee, uint256 referralFee, uint256 holdersFee, uint256 totalFee)
    {
        protocolFee = (price * feesEconomics.protocolFeePercent) / 1 ether;
        subjectFee = (price * feesEconomics.subjectFeePercent) / 1 ether;
        referralFee = (price * feesEconomics.referralFeePercent) / 1 ether;
        holdersFee = (price * feesEconomics.holdersFeePercent) / 1 ether;
        totalFee = protocolFee + subjectFee + referralFee + holdersFee;
    }

    function getPrice(uint256 supply, uint256 amount) public pure returns (uint256) {
        uint256 sum1 = supply == 0 ? 0 : ((supply - 1) * (supply) * (2 * (supply - 1) + 1)) / 6;
        uint256 sum2 = supply == 0 && amount == 1
            ? 0
            : ((supply - 1 + amount) * (supply + amount) * (2 * (supply - 1 + amount) + 1)) / 6;
        uint256 summation = sum2 - sum1;
        return (summation * 1 ether) / 16000;
    }

    function getBuyPrice(address curvesTokenSubject, uint256 amount) public view returns (uint256) {
        // getPrice(supply ,amount)
        return getPrice(curvesTokenSupply[curvesTokenSubject], amount);
    }

    function getSellPrice(address curvesTokenSubject, uint256 amount) public view returns (uint256) {
        //getPrice(supply - amount, amount)
        return getPrice(curvesTokenSupply[curvesTokenSubject] - amount, amount);
    }

    function getBuyPriceAfterFee(address curvesTokenSubject, uint256 amount) public view returns (uint256) {
        // price + fees
        uint256 price = getBuyPrice(curvesTokenSubject, amount);
        (,,,, uint256 totalFee) = getFees(price);

        return price + totalFee;
    }

    function getSellPriceAfterFee(address curvesTokenSubject, uint256 amount) public view returns (uint256) {
        //price -fees
        uint256 price = getSellPrice(curvesTokenSubject, amount);
        (,,,, uint256 totalFee) = getFees(price);

        return price - totalFee;
    }

    function buyCurvesToken(address curvesTokenSubject, uint256 amount) public payable {
        // buy token
        uint256 startTime = presalesMeta[curvesTokenSubject].startTime;
        if (startTime != 0 && startTime >= block.timestamp) revert SaleNotOpen(); // if sale is open

        _buyCurvesToken(curvesTokenSubject, amount);
    }

    function _transferFees(address curvesTokenSubject, bool isBuy, uint256 price, uint256 amount, uint256 supply)
        internal
    {
        (uint256 protocolFee, uint256 subjectFee, uint256 referralFee, uint256 holderFee,) = getFees(price); // price * fee%
        {
            bool referralDefined = referralFeeDestination[curvesTokenSubject] != address(0); //bool= is referral defined?
            {
                address firstDestination = isBuy ? feesEconomics.protocolFeeDestination : msg.sender; //if buying: owner <=> if selling:sender
                uint256 buyValue = referralDefined ? protocolFee : protocolFee + referralFee; // if referral defined:  (protocolFee) <=>  (protocolFees +  referralFees)
                uint256 sellValue = price - protocolFee - subjectFee - referralFee - holderFee; // price - totalFees

                // (bool success1,) = firstDestination.call{value: isBuy ? buyValue : sellValue}(""); // ok
                // if (!success1) revert CannotSendFunds();
                addressToUnclaimedFees[firstDestination] += isBuy? buyValue : sellValue;
            }
            {
                // (bool success2,) = curvesTokenSubject.call{value: subjectFee}(""); // send to subject
                // if (!success2) revert CannotSendFunds();
                addressToUnclaimedFees[curvesTokenSubject] += subjectFee;


            }
            {
                // (bool success3,) = referralDefined
                //     ? referralFeeDestination[curvesTokenSubject].call{value: referralFee}("") // send to referral
                //     : (true, bytes("")); // ok
                // if (!success3) revert CannotSendFunds();
                if(referralDefined){
                    addressToUnclaimedFees[referralFeeDestination[curvesTokenSubject]] += referralFee;
                }
            }

            if (feesEconomics.holdersFeePercent > 0 && address(feeRedistributor) != address(0)) {
                //if %>0 && holder is definded
                feeRedistributor.onBalanceChange(curvesTokenSubject, msg.sender); //
                feeRedistributor.addFees{value: holderFee}(curvesTokenSubject);
            }
        }
        emit Trade(
            msg.sender,
            curvesTokenSubject,
            isBuy,
            amount,
            price,
            protocolFee,
            subjectFee,
            isBuy ? supply + amount : supply - amount
        );
    }

    function _buyCurvesToken(address curvesTokenSubject, uint256 amount) internal {
        //@note you can send to much eth
        uint256 supply = curvesTokenSupply[curvesTokenSubject];
        if (!(supply > 0 || curvesTokenSubject == msg.sender)) revert UnauthorizedCurvesTokenSubject(); //if supply = 0 only subjectOwner can buy

        uint256 price = getPrice(supply, amount); // ok
        (,,,, uint256 totalFee) = getFees(price); //ok

        if (msg.value < price + totalFee) revert InsufficientPayment(); // ok msg.value  = (price+ totalfee)

        curvesTokenBalance[curvesTokenSubject][msg.sender] += amount; // + balance(sender)
        curvesTokenSupply[curvesTokenSubject] = supply + amount; // + supply
        _transferFees(curvesTokenSubject, true, price, amount, supply); // pay fees

        // If is the first token bought, add to the list of owned tokens
        if (curvesTokenBalance[curvesTokenSubject][msg.sender] - amount == 0) {
            // if balance(sender) was 0 => add token to his list
            _addOwnedCurvesTokenSubject(msg.sender, curvesTokenSubject); // add token
        }
    }

    function sellCurvesToken(address curvesTokenSubject, uint256 amount) public {
        uint256 supply = curvesTokenSupply[curvesTokenSubject];
        if (supply <= amount) revert LastTokenCannotBeSold();
        if (curvesTokenBalance[curvesTokenSubject][msg.sender] < amount) revert InsufficientBalance();

        uint256 price = getPrice(supply - amount, amount);

        curvesTokenBalance[curvesTokenSubject][msg.sender] -= amount;
        curvesTokenSupply[curvesTokenSubject] = supply - amount;

        _transferFees(curvesTokenSubject, false, price, amount, supply);
    }

    // Transfers tokens from current owner to receiver. Can be used for gifting or distributing tokens.
    function transferCurvesToken(address curvesTokenSubject, address to, uint256 amount) external {
        // transfer single token
        if (to == address(this)) revert ContractCannotReceiveTransfer();
        _transfer(curvesTokenSubject, msg.sender, to, amount);
    }

    // Transfer the total balance of all my tokens to another address. Can be used for migrating tokens.
    function transferAllCurvesTokens(address to) external {
        // loop all tokens
        if (to == address(this)) revert ContractCannotReceiveTransfer();
        address[] storage subjects = ownedCurvesTokenSubjects[msg.sender]; // subjectArr
        for (uint256 i = 0; i < subjects.length; i++) {
            //lopping
            uint256 amount = curvesTokenBalance[subjects[i]][msg.sender];
            if (amount > 0) {
                _transfer(subjects[i], msg.sender, to, amount); // transfer  sender => to
            }
        }
    }

    function _transfer(address curvesTokenSubject, address from, address to, uint256 amount) internal {
        //transfer token; to => from
        if (amount > curvesTokenBalance[curvesTokenSubject][from]) revert InsufficientBalance(); // low token balance(sender)

        // If transferring from oneself, skip adding to the list
        if (from != to) {
            // ok
            _addOwnedCurvesTokenSubject(to, curvesTokenSubject);
        }

        curvesTokenBalance[curvesTokenSubject][from] = curvesTokenBalance[curvesTokenSubject][from] - amount; //ok
        curvesTokenBalance[curvesTokenSubject][to] = curvesTokenBalance[curvesTokenSubject][to] + amount; //ok

        emit Transfer(curvesTokenSubject, from, to, amount);
    }

    // Internal function to add a curvesTokenSubject to the list if not already present
    function _addOwnedCurvesTokenSubject(address owner_, address curvesTokenSubject) internal {
        //add new subject to arr;; addr(owner) => subjects[] .push(subject)
        //@audit-ok: no dos attack
        address[] storage subjects = ownedCurvesTokenSubjects[owner_];
        for (uint256 i = 0; i < subjects.length; i++) {
            //check for duplicates
            if (subjects[i] == curvesTokenSubject) {
                return;
            }
        }
        subjects.push(curvesTokenSubject); // push
    }

    function _deployERC20( //deploy erc20
    address curvesTokenSubject, string memory name, string memory symbol)
        internal
        returns (address)
    {
        // If the token's symbol is CURVES, append a counter value
        if (keccak256(bytes(symbol)) == keccak256(bytes(DEFAULT_SYMBOL))) {
            _curvesTokenCounter += 1;
            name = string(abi.encodePacked(name, " ", Strings.toString(_curvesTokenCounter)));
            symbol = string(abi.encodePacked(symbol, Strings.toString(_curvesTokenCounter)));
        }

        if (symbolToSubject[symbol] != address(0)) revert InvalidERC20Metadata(); //if alredy exist?

        address tokenContract = CurvesERC20Factory(curvesERC20Factory).deploy(name, symbol, address(this)); // erc20 tokenContractAddr

        externalCurvesTokens[curvesTokenSubject].token = tokenContract; //set addr
        externalCurvesTokens[curvesTokenSubject].name = name; //set name
        externalCurvesTokens[curvesTokenSubject].symbol = symbol; // set symbol
        externalCurvesToSubject[tokenContract] = curvesTokenSubject; // set erc20Addr => addr(subject)
        symbolToSubject[symbol] = curvesTokenSubject; // symbol => addr(subject)

        emit TokenDeployed(curvesTokenSubject, tokenContract, name, symbol);
        return address(tokenContract);
    }

    function buyCurvesTokenWithName(
        address curvesTokenSubject,
        uint256 amount,
        string memory name,
        string memory symbol
    ) public payable {
        //buy and set name/symbol
        uint256 supply = curvesTokenSupply[curvesTokenSubject];
        if (supply != 0) revert CurveAlreadyExists(); // revert if alredy exist

        _buyCurvesToken(curvesTokenSubject, amount); // buy //@note only amount possible is 1?
        _mint(curvesTokenSubject, name, symbol); //deploy erc20
    }

    function buyCurvesTokenForPresale(
        address curvesTokenSubject,
        uint256 amount,
        uint256 startTime,
        bytes32 merkleRoot,
        uint256 maxBuy
    ) public payable onlyTokenSubject(curvesTokenSubject) {
        // set presele metadata
        if (startTime <= block.timestamp) revert InvalidPresaleStartTime(); // if startTime is in the past
        uint256 supply = curvesTokenSupply[curvesTokenSubject]; // supply of token
        if (supply != 0) revert CurveAlreadyExists(); // token alredy exist
        presalesMeta[curvesTokenSubject].startTime = startTime; //ok
        presalesMeta[curvesTokenSubject].merkleRoot = merkleRoot; //ok
        presalesMeta[curvesTokenSubject].maxBuy = (maxBuy == 0 ? type(uint256).max : maxBuy); // ok

        _buyCurvesToken(curvesTokenSubject, amount); // buy token; //@note only possible amount is 1?
    }

    function setWhitelist(bytes32 merkleRoot) external {// set/change merkleRoot (password)
        uint256 supply = curvesTokenSupply[msg.sender];
        if (supply > 1) revert CurveAlreadyExists();

        if (presalesMeta[msg.sender].merkleRoot != merkleRoot) {
            presalesMeta[msg.sender].merkleRoot = merkleRoot;
            emit WhitelistUpdated(msg.sender, merkleRoot);
        }
    }

    function buyCurvesTokenWhitelisted( // buy exclusive token; if in white list; proof == password
    address curvesTokenSubject, uint256 amount, bytes32[] memory proof)
        public
        payable
    {
        if (
            presalesMeta[curvesTokenSubject].startTime == 0 // if startTime not set
                || presalesMeta[curvesTokenSubject].startTime <= block.timestamp // or if is alredy open sale
        ) revert PresaleUnavailable();

        presalesBuys[curvesTokenSubject][msg.sender] += amount; //add token to user
        uint256 tokenBought = presalesBuys[curvesTokenSubject][msg.sender]; // amount bought by user
        if (tokenBought > presalesMeta[curvesTokenSubject].maxBuy) revert ExceededMaxBuyAmount(); //max limit buyable

        verifyMerkle(curvesTokenSubject, msg.sender, proof); // verify password(proof)
        _buyCurvesToken(curvesTokenSubject, amount); // buy token
    }

    function verifyMerkle(address curvesTokenSubject, address caller, bytes32[] memory proof) public view {    //ok but not verified
        // Verify merkle proof
        bytes32 leaf = keccak256(abi.encodePacked(caller));
        if (!MerkleProof.verify(proof, presalesMeta[curvesTokenSubject].merkleRoot, leaf)) revert UnverifiedProof();
    }

    function setNameAndSymbol(address curvesTokenSubject, string memory name, string memory symbol)
        external
        onlyTokenSubject(curvesTokenSubject)
    {
        if (externalCurvesTokens[curvesTokenSubject].token != address(0)) revert ERC20TokenAlreadyMinted(); //erc20 alredy deployed
        if (symbolToSubject[symbol] != address(0)) revert InvalidERC20Metadata(); // erc20 alredy deployed?
        externalCurvesTokens[curvesTokenSubject].name = name;
        externalCurvesTokens[curvesTokenSubject].symbol = symbol;
    }

    function mint(address curvesTokenSubject) external onlyTokenSubject(curvesTokenSubject) {
        //deploy external erc20 of msg.sender
        if (
            keccak256(abi.encodePacked(externalCurvesTokens[curvesTokenSubject].name))
                == keccak256(abi.encodePacked(""))
                || keccak256(abi.encodePacked(externalCurvesTokens[curvesTokenSubject].symbol))
                    == keccak256(abi.encodePacked(""))
        ) {
            externalCurvesTokens[curvesTokenSubject].name = DEFAULT_NAME;
            externalCurvesTokens[curvesTokenSubject].symbol = DEFAULT_SYMBOL;
        }
        _mint(
            curvesTokenSubject,
            externalCurvesTokens[curvesTokenSubject].name,
            externalCurvesTokens[curvesTokenSubject].symbol
        );
    }

    function _mint( //deploy erc20token
    address curvesTokenSubject, string memory name, string memory symbol)
        internal
        onlyTokenSubject(curvesTokenSubject)
    {
        if (externalCurvesTokens[curvesTokenSubject].token != address(0)) revert ERC20TokenAlreadyMinted(); //if token address != 0 => revert(alredy exits)
        _deployERC20(curvesTokenSubject, name, symbol);
    }

    function withdraw(address curvesTokenSubject, uint256 amount) public {
        //export erc20 , mint => msg.sender
        // mint erc20-token to msg.sender
        // transfer msg.sender => address(this)
        if (amount > curvesTokenBalance[curvesTokenSubject][msg.sender]) revert InsufficientBalance(); // ok revert insufficent tokenBalance(msg.sender)

        address externalToken = externalCurvesTokens[curvesTokenSubject].token; //externalTokenAddr
        if (externalToken == address(0)) {
            if ( // if empty name/symbol => go default
                keccak256(abi.encodePacked(externalCurvesTokens[curvesTokenSubject].name))
                    == keccak256(abi.encodePacked(""))
                    || keccak256(abi.encodePacked(externalCurvesTokens[curvesTokenSubject].symbol))
                        == keccak256(abi.encodePacked(""))
            ) {
                externalCurvesTokens[curvesTokenSubject].name = DEFAULT_NAME;
                externalCurvesTokens[curvesTokenSubject].symbol = DEFAULT_SYMBOL;
            }
            _deployERC20(
                curvesTokenSubject,
                externalCurvesTokens[curvesTokenSubject].name,
                externalCurvesTokens[curvesTokenSubject].symbol
            );
            externalToken = externalCurvesTokens[curvesTokenSubject].token;
        }
        _transfer(curvesTokenSubject, msg.sender, address(this), amount); // transfer msg.sender => curves
        CurvesERC20(externalToken).mint(msg.sender, amount * 1 ether); // mint sender erc20
    }

    function deposit(address curvesTokenSubject, uint256 amount) public {
        //deposit , burnToken(msg.sender)
        // burn burn erc20-token
        // transfer address(this)=> msg.sender
        if (amount % 1 ether != 0) revert NonIntegerDepositAmount(); // ok

        address externalToken = externalCurvesTokens[curvesTokenSubject].token; //externalTokenAddr
        uint256 tokenAmount = amount / 1 ether; // tokenAmount =  1  <= 1 ether

        if (externalToken == address(0)) revert TokenAbsentForCurvesTokenSubject(); // erc20 not deployed
        if (amount > CurvesERC20(externalToken).balanceOf(msg.sender)) revert InsufficientBalance(); // msg.sender low erc20 balance
        if (tokenAmount > curvesTokenBalance[curvesTokenSubject][address(this)]) revert InsufficientBalance(); // low curves token balance

        CurvesERC20(externalToken).burn(msg.sender, amount); // ok
        _transfer(curvesTokenSubject, address(this), msg.sender, tokenAmount); // ok
    }

    function sellExternalCurvesToken(address curvesTokenSubject, uint256 amount) public {
        //deposit and sellCurvesToken in one tx
        if (externalCurvesTokens[curvesTokenSubject].token == address(0)) revert TokenAbsentForCurvesTokenSubject(); // erc20 not deployed

        deposit(curvesTokenSubject, amount);
        sellCurvesToken(curvesTokenSubject, amount / 1 ether);
    }

    function withdrawFee() external {
        uint256 _feeAmount = addressToUnclaimedFees[msg.sender];
        if(_feeAmount == 0) revert InsufficientBalance();
        addressToUnclaimedFees[msg.sender] = 0;
        (bool success,) = (msg.sender).call{value: _feeAmount}("");
        if (!success) revert CannotSendFunds();
    }
}
