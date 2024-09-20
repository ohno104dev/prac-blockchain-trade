// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ITradingAccount.sol";

contract AccountRegistry is Ownable {
    event AccountCreated(address indexed owner, address indexed account);

    address public immutable weth;
    address public immutable usdc;
    address public immutable uniswapV2Pair;
    address public immutable cETH;
    address public immutable cUSDC;
    address public immutable comptroller;
    address public immutable priceFeed;
    address public immutable accountTemplate;
    mapping(address => address) public getAccount;

    constructor(
        address weth_,
        address usdc_,
        address uniswapV2Pair_,
        address cETH_,
        address cUSDC_,
        address comptroller_,
        address priceFeed_,
        address accountTemplate_
    ) Ownable(msg.sender) {
        weth = weth_;
        usdc = usdc_;
        uniswapV2Pair = uniswapV2Pair_;
        cETH = cETH_;
        cUSDC = cUSDC_;
        comptroller = comptroller_;
        priceFeed = priceFeed_;
        accountTemplate = accountTemplate_;
    }

    function createAccount() external returns (address) {
        require(getAccount[msg.sender] == address(0), "account exists");
        address account = Clones.clone(accountTemplate);
        ITradingAccount(account).initialize(
            msg.sender,
            weth,
            usdc,
            uniswapV2Pair,
            cETH,
            cUSDC,
            comptroller,
            priceFeed
        );
        getAccount[msg.sender] = account;
        emit AccountCreated(msg.sender, account);
        return account;
    }
}