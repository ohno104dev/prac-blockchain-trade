// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICEther {
    function mint() external payable;

    function redeem(uint256 redeemTokens) external returns (uint256);

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function borrow(uint256 borrowAmount) external returns (uint256);

    function repayBorrow() external payable;

    function borrowBalanceStored(address account) external view returns (uint256);

    function getAccountSnapshot(address account) external view returns(
        uint,
        uint,
        uint,
        uint
    );
}