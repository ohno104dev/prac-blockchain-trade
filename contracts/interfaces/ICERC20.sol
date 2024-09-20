// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICERC20 {
    function mint(uint256 mintAmount) external returns (uint256);

    function redeem(uint256 redeemTokens) external returns (uint256);

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function borrow(uint256 borrowAmount) external returns (uint256);

    function repayBorrow(uint256 repayAmount) external returns (uint);

    function borrowBalanceStored(address account) external view returns (uint256);

    function getAccountSnapshot(address account) external view returns(
        uint,
        uint,
        uint,
        uint
    );
}