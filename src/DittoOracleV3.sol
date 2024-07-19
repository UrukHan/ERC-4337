// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

import {IDittoOracleV3} from "./vault/interfaces/IDittoOracleV3.sol";
import {UniswapOracleLibrary} from "./vault/libraries/external/UniswapOracleLibrary.sol";
import {DexLogicLib} from "./vault/libraries/DexLogicLib.sol";

/// @title DittoOracleV3
/// @notice DittoOracleV3 is a contract for Ditto's Uniswap V3 Oracle
/// @dev This contract is used to get the average price of tokens for the last 60 seconds
/// @dev Code is copied from:
/// https://github.com/Uniswap/v3-periphery/blob/main/contracts/libraries/OracleLibrary.sol#L49
contract DittoOracleV3 is IDittoOracleV3 {
    // =========================
    // Storage
    // =========================

    /// @inheritdoc IDittoOracleV3
    uint256 public constant PERIOD = 60; // in seconds

    // =========================
    // Main function
    // =========================

    /// @inheritdoc IDittoOracleV3
    function consult(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint24 fee,
        address dexFactory
    ) external view returns (uint256 quoteAmount) {
        address pool = IUniswapV3Factory(dexFactory).getPool(
            tokenIn,
            tokenOut,
            fee
        );

        // if pool does not exists -> revert
        if (pool == address(0)) {
            revert UniswapOracle_PoolNotFound();
        }

        int24 timeWeightedAverageTick = UniswapOracleLibrary.consultView(
            pool,
            uint32(PERIOD)
        );

        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(
            timeWeightedAverageTick
        );

        quoteAmount = tokenIn < tokenOut
            ? DexLogicLib.getAmount0InToken1(sqrtRatioX96, amountIn)
            : DexLogicLib.getAmount1InToken0(sqrtRatioX96, amountIn);
    }
}
