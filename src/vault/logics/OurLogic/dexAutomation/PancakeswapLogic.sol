// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IV3SwapRouter} from "../../../interfaces/external/IV3SwapRouter.sol";
import {IWETH9} from "../../../interfaces/external/IWETH9.sol";

import {BaseContract} from "../../../libraries/BaseContract.sol";

import {DexBaseLogic} from "./DexBaseLogic.sol";

import {IPancakeswapLogic} from "../../../interfaces/ourLogic/dexAutomation/IPancakeswapLogic.sol";

/// @title PancakeswapLogic.
/// @notice This contract contains logic for operations related to Pancakeswap V3.
contract PancakeswapLogic is IPancakeswapLogic, DexBaseLogic, BaseContract {
    // =========================
    // Constructor
    // =========================

    /// @notice Sets the immutable variables for the contract.
    /// @param _cakeNftPositionManager Instance of the Pancakeswap Nonfungible Position Manager.
    /// @param _pancakeswapRouter Instance of the Pancakeswap V3 Swap Router.
    /// @param _pancakeswapFactory Instance of the Pancakeswap V3 Factory.
    constructor(
        INonfungiblePositionManager _cakeNftPositionManager,
        IV3SwapRouter _pancakeswapRouter,
        IUniswapV3Factory _pancakeswapFactory,
        IWETH9 _wNative
    )
        DexBaseLogic(
            _cakeNftPositionManager,
            _pancakeswapRouter,
            _pancakeswapFactory,
            _wNative
        )
    {}

    // =========================
    // Main functions
    // =========================

    /// @inheritdoc IPancakeswapLogic
    function pancakeswapChangeTickRange(
        int24 newLowerTick,
        int24 newUpperTick,
        uint256 nftId,
        uint256 deviationThresholdE18
    ) external onlyVaultItself returns (uint256) {
        uint256 newNftId = _changeTickRange(
            newLowerTick,
            newUpperTick,
            nftId,
            deviationThresholdE18
        );

        emit PancakeswapChangeTickRange(nftId, newNftId);

        return newNftId;
    }

    /// @inheritdoc IPancakeswapLogic
    function pancakeswapMintNft(
        IUniswapV3Pool pancakeswapPool,
        int24 newLowerTick,
        int24 newUpperTick,
        uint256 token0Amount,
        uint256 token1Amount,
        bool useFullTokenBalancesFromVault,
        bool swap,
        uint256 deviationThresholdE18
    ) external onlyVaultItself returns (uint256) {
        uint256 newNftId = _mintNft(
            pancakeswapPool,
            newLowerTick,
            newUpperTick,
            token0Amount,
            token1Amount,
            useFullTokenBalancesFromVault,
            swap,
            deviationThresholdE18
        );

        emit PancakeswapMintNft(newNftId);

        return newNftId;
    }

    /// @inheritdoc IPancakeswapLogic
    function pancakeswapAddLiquidity(
        uint256 nftId,
        uint256 token0Amount,
        uint256 token1Amount,
        bool useFullTokenBalancesFromVault,
        bool swap,
        uint256 deviationThresholdE18
    ) external onlyVaultItself {
        _addLiquidity(
            nftId,
            token0Amount,
            token1Amount,
            useFullTokenBalancesFromVault,
            swap,
            deviationThresholdE18
        );
        emit PancakeswapAddLiquidity(nftId);
    }

    /// @inheritdoc IPancakeswapLogic
    function pancakeswapAutoCompound(
        uint256 nftId,
        uint256 deviationThresholdE18
    ) external onlyVaultItself {
        _autoCompound(nftId, deviationThresholdE18);

        emit PancakeswapAutoCompound(nftId);
    }

    /// @inheritdoc IPancakeswapLogic
    function pancakeswapSwapExactInput(
        address[] calldata tokens,
        uint24[] calldata poolFees,
        uint256 amountIn,
        bool useFullBalanceOfTokenInFromVault,
        bool unwrapInTheEnd,
        uint256 deviationThresholdE18
    ) external onlyVaultItself returns (uint256 amountOut) {
        amountOut = _swapExactInput(
            tokens,
            poolFees,
            amountIn,
            useFullBalanceOfTokenInFromVault,
            unwrapInTheEnd,
            deviationThresholdE18
        );
    }

    /// @inheritdoc IPancakeswapLogic
    function pancakeswapSwapExactOutputSingle(
        address tokenIn,
        address tokenOut,
        uint24 poolFee,
        uint256 amountOut,
        uint256 deviationThresholdE18
    ) external onlyVaultItself returns (uint256 amountIn) {
        amountIn = _swapExactOutputSingle(
            tokenIn,
            tokenOut,
            poolFee,
            amountOut,
            deviationThresholdE18
        );
    }

    /// @inheritdoc IPancakeswapLogic
    function pancakeswapSwapToTargetR(
        uint256 deviationThresholdE18,
        IUniswapV3Pool pancakeswapPool,
        uint256 token0Amount,
        uint256 token1Amount,
        uint256 targetRE18
    ) external onlyVaultItself returns (uint256, uint256) {
        (token0Amount, token1Amount) = _swapToTargetR(
            deviationThresholdE18,
            pancakeswapPool,
            token0Amount,
            token1Amount,
            targetRE18
        );

        return (token0Amount, token1Amount);
    }

    /// @inheritdoc IPancakeswapLogic
    function pancakeswapWithdrawPositionByShares(
        uint256 nftId,
        uint128 sharesE18,
        uint256 deviationThresholdE18
    ) external onlyVaultItself {
        _withdrawPositionByShares(nftId, sharesE18, deviationThresholdE18);

        emit PancakeswapWithdraw(nftId);
    }

    /// @inheritdoc IPancakeswapLogic
    function pancakeswapWithdrawPositionByLiquidity(
        uint256 nftId,
        uint128 liquidity,
        uint256 deviationThresholdE18
    ) external onlyVaultItself {
        _withdrawPositionByLiquidity(nftId, liquidity, deviationThresholdE18);

        emit PancakeswapWithdraw(nftId);
    }

    /// @inheritdoc IPancakeswapLogic
    function pancakeswapCollectFees(uint256 nftId) external onlyVaultItself {
        _collectFees(nftId);
    }
}
