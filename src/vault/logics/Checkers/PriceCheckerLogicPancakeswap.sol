// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {BaseContract} from "../../libraries/BaseContract.sol";
import {PriceCheckerLogicBase} from "./PriceCheckerLogicBase.sol";

import {IDittoOracleV3} from "../../interfaces/IDittoOracleV3.sol";
import {IPriceCheckerLogicPancakeswap} from "../../interfaces/checkers/IPriceCheckerLogicPancakeswap.sol";

/// @title PriceCheckerLogicPancakeswap
contract PriceCheckerLogicPancakeswap is
    IPriceCheckerLogicPancakeswap,
    BaseContract,
    PriceCheckerLogicBase
{
    // =========================
    // Constructor
    // =========================

    constructor(
        IDittoOracleV3 _dittoOracle,
        address _pancakeFactory
    ) PriceCheckerLogicBase(_dittoOracle, _pancakeFactory) {}

    // =========================
    // Initializer
    // =========================

    /// @inheritdoc IPriceCheckerLogicPancakeswap
    function priceCheckerPancakeswapInitialize(
        IUniswapV3Pool pancakeswapPool,
        uint256 targetRate,
        bytes32 pointer
    ) external onlyVaultItself {
        _priceCheckerInitialize(pancakeswapPool, targetRate, pointer);
    }

    // =========================
    // Main functions
    // =========================

    /// @inheritdoc IPriceCheckerLogicPancakeswap
    function pancakeswapCheckGTTargetRate(
        bytes32 pointer
    ) external view returns (bool) {
        return _checkGTTargetRate(pointer);
    }

    /// @inheritdoc IPriceCheckerLogicPancakeswap
    function pancakeswapCheckGTETargetRate(
        bytes32 pointer
    ) external view returns (bool) {
        return _checkGTETargetRate(pointer);
    }

    /// @inheritdoc IPriceCheckerLogicPancakeswap
    function pancakeswapCheckLTTargetRate(
        bytes32 pointer
    ) external view returns (bool) {
        return _checkLTTargetRate(pointer);
    }

    /// @inheritdoc IPriceCheckerLogicPancakeswap
    function pancakeswapCheckLTETargetRate(
        bytes32 pointer
    ) external view returns (bool) {
        return _checkLTETargetRate(pointer);
    }

    // =========================
    // Setters
    // =========================

    /// @inheritdoc IPriceCheckerLogicPancakeswap
    function pancakeswapChangeTokensAndFeePriceChecker(
        IUniswapV3Pool pancakeswapPool,
        bytes32 pointer
    ) external onlyOwnerOrVaultItself {
        _changeTokensAndFeePriceChecker(pancakeswapPool, pointer);
    }

    /// @inheritdoc IPriceCheckerLogicPancakeswap
    function pancakeswapChangeTargetRate(
        uint256 targetRate,
        bytes32 pointer
    ) external onlyOwnerOrVaultItself {
        _changeTargetRate(targetRate, pointer);
    }

    // =========================
    // Getters
    // =========================

    /// @inheritdoc IPriceCheckerLogicPancakeswap
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
        )
    {
        PriceCheckerStorage storage pcs = _getStorageUnsafe(pointer);

        return (
            pcs.token0,
            pcs.token1,
            pcs.fee,
            pcs.targetRate,
            pcs.initialized
        );
    }
}
