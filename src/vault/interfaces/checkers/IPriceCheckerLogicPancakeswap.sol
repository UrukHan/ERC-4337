// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IPriceCheckerLogicBase} from "./IPriceCheckerLogicBase.sol";

/// @title IPriceCheckerLogicPancakeswap - PriceCheckerLogicPancakeswap interface.
interface IPriceCheckerLogicPancakeswap is IPriceCheckerLogicBase {
    // =========================
    // Initializer
    // =========================

    /// @notice Initializes the price checker
    /// @param pancakeswapPool The pancakeswap pool to check the price from.
    /// @param targetRate The target exchange rate between the tokens.
    /// @param pointer The bytes32 pointer value.
    function priceCheckerPancakeswapInitialize(
        IUniswapV3Pool pancakeswapPool,
        uint256 targetRate,
        bytes32 pointer
    ) external;

    // =========================
    // Main functions
    // =========================

    /// @notice Checks if the current rate is greater than the target rate.
    /// @param pointer The bytes32 pointer value.
    /// @return true if the current rate is greater than the target rate, otherwise false.
    function pancakeswapCheckGTTargetRate(
        bytes32 pointer
    ) external view returns (bool);

    /// @notice Checks if the current rate is greater than or equal to the target rate.
    /// @param pointer The bytes32 pointer value.
    /// @return bool indicating whether the current rate is greater than or equal to the target rate.
    function pancakeswapCheckGTETargetRate(
        bytes32 pointer
    ) external view returns (bool);

    /// @notice Checks if the current rate is less than the target rate.
    /// @param pointer The bytes32 pointer value.
    /// @return true if the current rate is less than the target rate, otherwise false.
    function pancakeswapCheckLTTargetRate(
        bytes32 pointer
    ) external view returns (bool);

    /// @notice Checks if the current rate is less than or equal to the target rate.
    /// @param pointer The bytes32 pointer value.
    /// @return bool indicating whether the current rate is less than or equal to the target rate.
    function pancakeswapCheckLTETargetRate(
        bytes32 pointer
    ) external view returns (bool);

    // =========================
    // Setters
    // =========================

    /// @notice Sets the tokens and feeTier from the pair to checker storage.
    /// @param pancakeswapPool The pancakeswap pool to fetch the tokens and fee from.
    /// @param pointer The bytes32 pointer value.
    function pancakeswapChangeTokensAndFeePriceChecker(
        IUniswapV3Pool pancakeswapPool,
        bytes32 pointer
    ) external;

    /// @notice Set the target rate of the contract.
    /// @param targetRate The new target rate to be set.
    /// @param pointer The bytes32 pointer value.
    function pancakeswapChangeTargetRate(
        uint256 targetRate,
        bytes32 pointer
    ) external;

    // =========================
    // Getters
    // =========================

    /// @notice Retrieves the local price checker storage values.
    /// @param pointer The bytes32 pointer value.
    /// @return token0 The address of the first token.
    /// @return token1 The address of the second token.
    /// @return fee The fee for the pool.
    /// @return targetRate The target exchange rate set for the tokens.
    /// @return initialized A boolean indicating if the contract has been initialized or not.
    function pancakeswapGetLocalPriceCheckerStorage(
        bytes32 pointer
    )
        external
        view
        returns (
            address token0,
            address token1,
            uint24 fee,
            uint256 targetRate,
            bool initialized
        );
}
