// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITradingAccount {
    event Deposit(bool isETH, uint256 account, uint256 cTokenAmount);
    event Withdraw(bool isETH, uint256 cTokenAmount, uint256 underlyingAmount);
    event OpenLong(uint256 ethSize, uint256 cTokenMint, uint256 borrowAmount);  
    event OpenShort(uint256 usdcSize, uint256 cTokenMint, uint256 borrowAmount);    
    event CloseLong(    
        uint256 redeemCTokenAmount,
        uint256 redeemUnderlyingAmount,
        uint256 repayAmount,
        bool closeAll
    );
    event CloseShort(   
        uint256 redeemCtokenAmount,
        uint256 redeemUnderlyingAmount,
        uint256 repayAmount,
        bool closeAll
    );
    event LimitOpenLong(    
        uint256 orderId,
        uint256 ethSize,
        uint256 limitPrice,
        uint256 expireAt,
        address indexed keeper
    );
    event LimitOpenShort(
        uint256 orderId,
        uint256 usdcSize,
        uint256 limitPrice,
        uint256 expireAt,
        address indexed keeper
    ); 
    event CancelLimitOrder(uint256 orderId);   
    event ExecuteLimitOrder(uint256 orderId, uint256 dealPrice);   

    struct LimitOrder {
        bool isLong;
        bool isCanceled;
        uint256 openSize;
        uint256 limitPrice;
        uint256 dealPrice;
        uint256 expireAt;
        address keeper;
    }

    function initialize(
        address owner,
        address weth,
        address usdc,
        address uniswapV2Pair,
        address cETH,
        address cUSDC,
        address comptroller,
        address priceFeed
    ) external;
}