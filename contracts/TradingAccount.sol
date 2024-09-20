// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

import "./interfaces/IWETH.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Callee.sol";
import "./interfaces/ICEther.sol";
import "./interfaces/ICERC20.sol";
import "./interfaces/IComptroller.sol";
import "./interfaces/ITradingAccount.sol";
import "./base/Ownable.sol";
import "./libraries/TransferHelper.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract TradingAccount is 
    ITradingAccount,
    IUniswapV2Callee,
    Initializable,
    Ownable
{
    // address public owner;
    address public weth;
    address public usdc;
    address public uniswapV2Pair;
    address public cETH;
    address public cUSDC;
    address public comptroller;
    address public priceFeed;
    uint256 public lastOrderId;
    mapping(uint256 => LimitOrder) public getLimitOrder;

    struct TempParams {
        bool isOpen;
        bool isLong;
        uint256 openSize;
        uint256 borrowedAmount;
        uint256 cTokenMinted;
        uint256 cTokenRedeemed;
        uint256 underlyingRedeemed;
        uint256 repayAmount;
    }
    TempParams private tempParams;

    uint256 public lastCEthBalance;
    uint256 public lastCUsdcBalance;

    receive() external payable {
        assert(msg.sender == weth); // only accept ETH via fallback from the WETH contract
    }

    function initialize(
        address owner_,
        address weth_,
        address usdc_,
        address uniswapV2Pair_,
        address cETH_,
        address cUSDC_,
        address comptroller_,
        address priceFeed_
    ) external override initializer {
        transferOwnership(owner_);
        weth = weth_;
        usdc = usdc_;
        uniswapV2Pair = uniswapV2Pair_;
        cETH = cETH_;
        cUSDC = cUSDC_;
        comptroller = comptroller_;
        priceFeed = priceFeed_;
        address[] memory cTokens = new address[](2);
        cTokens[0] = cETH;
        cTokens[1] = cUSDC;
        IComptroller(comptroller).enterMarkets(cTokens);
    }

    function depositETH() external payable onlyOwner {
        uint256 depositAmount = msg.value;
        ICEther(cETH).mint{value: depositAmount}();
        uint256 cEthBalance = IERC20(cETH).balanceOf(address(this));
        uint256 cEthAmountGet = cEthBalance - lastCEthBalance;
        lastCEthBalance = cEthBalance;
        emit Deposit(true, depositAmount, cEthAmountGet);
    }

    function depositUSDC(uint256 amount) external payable onlyOwner {
        TransferHelper.safeTransferFrom(
            usdc,
            msg.sender,
            address(this),
            amount
        );
        IERC20(usdc).approve(cUSDC, amount);    // compound 授權
        require(ICERC20(cUSDC).mint(amount) == 0, "mint error");
        uint256 cUsdcBalance = IERC20(cUSDC).balanceOf(address(this));
        uint256 cUsdcAmountGet = cUsdcBalance - lastCUsdcBalance;
        lastCEthBalance = cUsdcBalance;
        emit Deposit(false, amount, cUsdcAmountGet);
    }

    function withdrawETH(uint256 cEthAmount, uint256 ethAmount) 
        external
        onlyOwner
    {
        require(
            (cEthAmount > 0 && ethAmount == 0) || (cEthAmount == 0 && ethAmount > 0),
            "one must be zero, one must be gt 0"
        );
        if (cEthAmount > 0) {
            require(ICEther(cETH).redeem(cEthAmount) == 0, "redeem error");
        } else {
            require(
                ICEther(cETH).redeemUnderlying(ethAmount) == 0,
                "redeem error"
            );
        }
        uint256 cTokenBalanceNew = IERC20(cETH).balanceOf(address(this));
        cEthAmount = lastCEthBalance - cTokenBalanceNew;
        lastCEthBalance = cTokenBalanceNew;
        ethAmount = address(this).balance;

        TransferHelper.safeTransferETH(msg.sender, address(this).balance);
        emit Withdraw(true, cEthAmount, ethAmount);
    }

    function withdrawUSDC(uint256 cUsdcAmount, uint256 usdcAmount) 
        external
        onlyOwner
    {
        require(
            (cUsdcAmount > 0 && usdcAmount == 0) || (cUsdcAmount == 0 && usdcAmount > 0),
            "one must be zero, one must be gt 0"
        );
        if (cUsdcAmount > 0) {
            require(ICERC20(cUSDC).redeem(cUsdcAmount) == 0, "redeem error");
        } else {
            require(
                ICERC20(cUSDC).redeemUnderlying(usdcAmount) == 0,
                "redeem error"
            );
        }
        uint256 cTokenBalanceNew = IERC20(cUSDC).balanceOf(address(this));
        cUsdcAmount = lastCUsdcBalance - cTokenBalanceNew;
        lastCUsdcBalance = cTokenBalanceNew;
        usdcAmount = IERC20(usdc).balanceOf(address(this));

        TransferHelper.safeTransfer(usdc, msg.sender, usdcAmount);
        emit Withdraw(false, cUsdcAmount, usdcAmount);
    }

    function openLong(uint256 ethSize) external onlyOwner {
        _openLong(ethSize);
    }

    function openShort(uint256 usdcSize) external onlyOwner {
        _openShort(usdcSize);
    }

    function closeLong(uint256 usdcAmount, bool closeAll) 
        external  
        onlyOwner 
        returns (uint256 repayAmount)
    {
        uint256 borrowBalance = ICERC20(cUSDC).borrowBalanceStored(
            address(this)
        );
        repayAmount = closeAll ? borrowBalance : usdcAmount;

        address token0 = IUniswapV2Pair(uniswapV2Pair).token0();
        uint256 amount0Out;
        uint256 amount1Out;
        if (token0 == usdc) {
            amount0Out = repayAmount;
        } else {
            amount1Out = repayAmount;
        }
        tempParams = TempParams(false, true, 0, 0, 0, 0, 0, repayAmount);
        IUniswapV2Pair(uniswapV2Pair).swap(
            amount0Out,
            amount1Out,
            address(this),
            "0x1234"
        );
        uint256 cTokenBalanceNew = IERC20(cETH).balanceOf(address(this));
        uint256 redeemdCToken = lastCEthBalance - cTokenBalanceNew;
        lastCEthBalance = cTokenBalanceNew;
        emit CloseLong(
            redeemdCToken,
            tempParams.underlyingRedeemed,
            repayAmount,
            closeAll
        );
        delete tempParams;
    }

    function closeShort(uint256 ethAmount, bool closeAll) 
        external  
        onlyOwner 
        returns (uint256 repayAmount)
    {
        uint256 borrowBalance = ICEther(cETH).borrowBalanceStored(
            address(this)
        );
        repayAmount = closeAll ? borrowBalance : ethAmount;

        address token0 = IUniswapV2Pair(uniswapV2Pair).token0();
        uint256 amount0Out;
        uint256 amount1Out;
        if (token0 == weth) {
            amount0Out = repayAmount;
        } else {
            amount1Out = repayAmount;
        }
        tempParams = TempParams(false, true, 0, 0, 0, 0, 0, repayAmount);
        IUniswapV2Pair(uniswapV2Pair).swap(
            amount0Out,
            amount1Out,
            address(this),
            "0x1234"
        );
        uint256 cTokenBalanceNew = IERC20(cUSDC).balanceOf(address(this));
        uint256 redeemdCToken = lastCUsdcBalance - cTokenBalanceNew;
        lastCUsdcBalance = cTokenBalanceNew;
        emit CloseShort(
            redeemdCToken,
            tempParams.underlyingRedeemed,
            repayAmount,
            closeAll
        );
        delete tempParams;
    }

    function limitOpenLong(
        uint256 ethSize,
        uint256 limitPrice,
        uint256 expireAt,
        address keeper
    ) external onlyOwner returns (uint256 orderId) {
        orderId = _newLimitOrder(true, ethSize, limitPrice, expireAt, keeper);
        emit LimitOpenLong(orderId, ethSize, limitPrice, expireAt, keeper);
    }

    function limitOpenShort(
        uint256 usdcSize,
        uint256 limitPrice,
        uint256 expireAt,
        address keeper
    ) external onlyOwner returns (uint256 orderId) {
        orderId = _newLimitOrder(false, usdcSize, limitPrice, expireAt, keeper);
        emit LimitOpenShort(orderId, usdcSize, limitPrice, expireAt, keeper);
    }

    function cancelLimitOrder(uint256 orderId) external onlyOwner {
        require(orderId > 0 && orderId <= lastOrderId, "order not found");
        LimitOrder memory order = getLimitOrder[orderId];
        require(!order.isCanceled, "already canceled");
        require(order.dealPrice == 0, "already dealt");
        require(order.expireAt > block.timestamp, "already expired");
        order.isCanceled = true;
        getLimitOrder[orderId] = order;

        emit CancelLimitOrder(orderId);
    }

    function executeLimitOrder(uint256 orderId) external {
        require(orderId > 0 && orderId <= lastOrderId, "order not found");
        LimitOrder memory order = getLimitOrder[orderId];
        require(order.keeper == msg.sender, "require keeper");
        require(!order.isCanceled, "already canceled");
        require(order.dealPrice == 0, "already dealt");
        require(order.expireAt > block.timestamp, "already expired");

        uint256 latestPrice = getLatestPrice();
        if (order.isLong) {
            require(order.limitPrice >= latestPrice, "not reach limitPrice");
            _openLong(order.openSize);
        } else {
            require(order.limitPrice <= latestPrice, "not rach limitPrice");
            _openShort(order.openSize);
        }

        emit ExecuteLimitOrder(orderId, latestPrice);
    }

    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external {
        require(msg.sender == uniswapV2Pair, "only uniswapV2Pair");
        address token0 = IUniswapV2Pair(uniswapV2Pair).token0();
        address token1 = IUniswapV2Pair(uniswapV2Pair).token1();
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(uniswapV2Pair).getReserves();

        address tokenOutput;
        uint256 reserveIn;
        uint256 reserveOut;
        uint256 amountOut;

        if (amount0 > 0) {
            tokenOutput = token0;
            reserveIn = reserve1;
            reserveOut = reserve0;
            amountOut = amount0;
        } else {
            tokenOutput = token1;
            reserveIn = reserve0;
            reserveOut = reserve1;
            amountOut = amount1;
        }
        uint256 amountIn = _getAmountIn(amountOut, reserveIn, reserveOut);

        if (tempParams.isOpen) {
            tempParams.borrowedAmount = amountIn;
            if (tempParams.isLong) {
                IWETH(weth).withdraw(amountOut);
                ICEther(cETH).mint{value: amountOut}();
                require(ICERC20(cUSDC).borrow(amountIn) == 0, "borrow error");
                TransferHelper.safeTransfer(usdc, uniswapV2Pair, amountIn);
            } else {
                TransferHelper.safeApprove(usdc,cUSDC, amountOut);
                require(ICERC20(cUSDC).mint(amountOut) == 0, "mint error");
                require(ICEther(cETH).borrow(amountIn) == 0, "borrow error");
                IWETH(weth).deposit{value: amountIn}();
                TransferHelper.safeTransfer(weth, uniswapV2Pair, amountIn);
            }
        } else {
            tempParams.underlyingRedeemed = amountIn;
            if (tempParams.isLong) {
                TransferHelper.safeApprove(usdc, cUSDC, amountOut);
                require(
                    ICERC20(cUSDC).repayBorrow(amountOut) == 0,
                    "repay error"
                );
                require(
                    ICEther(cETH).redeemUnderlying(amountIn) == 0,
                    "redeem error"
                );
                IWETH(weth).deposit{value: amountIn}();
                TransferHelper.safeTransfer(weth, uniswapV2Pair, amountIn);
            } else {
                ICEther(cETH).repayBorrow{value: amountOut}();
                require(
                    ICERC20(cUSDC).redeemUnderlying(amountIn) == 0,
                    "redeem error"
                );
                TransferHelper.safeTransfer(usdc, uniswapV2Pair, amountIn);
            }
        }
    }

    function getLatestPrice() public view returns (uint256) {
        (, int256 price, , , ) = AggregatorV3Interface(priceFeed).latestRoundData();
        return uint256(price);
    }

    function _openLong(uint256 ethSize) internal {
        address token0 = IUniswapV2Pair(uniswapV2Pair).token0();
        uint256 amount0Out;
        uint256 amount1Out;
        if (token0 == weth) {
            amount0Out = ethSize;
        } else {
            amount1Out = ethSize;
        }

        tempParams = TempParams(true, true, ethSize, 0, 0, 0, 0, 0);
        IUniswapV2Pair(uniswapV2Pair).swap(
            amount0Out,
            amount1Out,
            address(this),
            "0x1234"
        );

        uint256 cEthBalance = IERC20(cETH).balanceOf(address(this));
        uint256 cEthAmountGet = cEthBalance - lastCEthBalance;
        lastCEthBalance = cEthBalance;
        emit OpenLong(ethSize, cEthAmountGet, tempParams.borrowedAmount);
        delete tempParams;
    }

    function _openShort(uint256 usdcSize) internal {
        address token0 = IUniswapV2Pair(uniswapV2Pair).token0();
        uint256 amount0Out;
        uint256 amount1Out;
        if (token0 == usdc) {
            amount0Out = usdcSize;
        } else {
            amount1Out = usdcSize;
        }

        tempParams = TempParams(true, false, usdcSize, 0, 0, 0, 0, 0);
        IUniswapV2Pair(uniswapV2Pair).swap(
            amount0Out,
            amount1Out,
            address(this),
            "0x1234"
        );

        uint256 cUsdcBalance = IERC20(cUSDC).balanceOf(address(this));
        uint256 cUsdcAmountGet = cUsdcBalance - lastCUsdcBalance;
        lastCUsdcBalance = cUsdcBalance;
        emit OpenShort(usdcSize, cUsdcAmountGet, tempParams.borrowedAmount);
        delete tempParams;
    }

    function _newLimitOrder(
        bool isLong,
        uint256 openSize,
        uint256 limitPrice,
        uint256 expireAt,
        address keeper
    ) internal returns (uint256 orderId) {
        require(expireAt > block.timestamp, "expireAt <= block.timestamp");
        if (isLong) {
            require(limitPrice < getLatestPrice(), "limitPrice >= latestPrice");
        } else {
            require(limitPrice > getLatestPrice(), "limitPrice <= latestPrice");
        }

        LimitOrder memory order = LimitOrder({
            isLong: isLong,
            isCanceled: false,
            openSize: openSize,
            limitPrice: limitPrice,
            dealPrice: 0,
            expireAt: expireAt,
            keeper: keeper
        });
        lastOrderId += 1;
        getLimitOrder[lastOrderId] = order;
        orderId = lastOrderId;
        return orderId;
    }

    function _getAmountOut(
        uint amountIn,
        uint reserveIn,
        uint reserveOut
    ) internal pure  returns (uint amountOut) {
        require(amountIn > 0, "INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        uint amountInWithFee = amountIn * 997;
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function _getAmountIn(
        uint amountOut,
        uint reserveIn,
        uint reserveOut
    ) internal pure  returns (uint amountIn) {
        require(amountOut > 0, "INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");
        uint numerator = amountIn * amountOut * 1000;
        uint denominator = (reserveOut - amountOut) * 997;
        amountIn = numerator / denominator + 1;
    }
}