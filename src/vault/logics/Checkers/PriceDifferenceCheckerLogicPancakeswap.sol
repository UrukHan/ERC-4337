// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {IDittoOracleV3} from "../../interfaces/IDittoOracleV3.sol";
import {IPriceDifferenceCheckerLogicPancakeswap} from "../../interfaces/checkers/IPriceDifferenceCheckerLogicPancakeswap.sol";

import {BaseContract} from "../../libraries/BaseContract.sol";
import {PriceDifferenceCheckerLogicBase} from "./PriceDifferenceCheckerLogicBase.sol";

/// @title PriceDifferenceCheckerLogicPancakeswap
contract PriceDifferenceCheckerLogicPancakeswap is
    IPriceDifferenceCheckerLogicPancakeswap,
    PriceDifferenceCheckerLogicBase,
    BaseContract
{
    // =========================
    // Constructor
    // =========================

    constructor(
        IDittoOracleV3 _dittoOracle,
        address _pancakeFactory
    ) PriceDifferenceCheckerLogicBase(_dittoOracle, _pancakeFactory) {}

    // =========================
    // Initializer
    // =========================

    /// @inheritdoc IPriceDifferenceCheckerLogicPancakeswap
    function priceDifferenceCheckerPancakeswapInitialize(
        IUniswapV3Pool pancakeswapPool,
        uint24 percentageDeviation_E3,
        bytes32 pointer
    ) external onlyVaultItself {
        _priceDifferenceCheckerInitialize(
            pancakeswapPool,
            percentageDeviation_E3,
            pointer
        );
    }

    // =========================
    // Main functions
    // =========================

    /// @inheritdoc IPriceDifferenceCheckerLogicPancakeswap
    function pancakeswapCheckPriceDifference(
        bytes32 pointer
    ) external onlyVaultItself returns (bool success) {
        return _checkPriceDifference(pointer);
    }

    /// @inheritdoc IPriceDifferenceCheckerLogicPancakeswap
    function pancakeswapCheckPriceDifferenceView(
        bytes32 pointer
    ) external view returns (bool success) {
        return _checkPriceDifferenceView(pointer);
    }

    // =========================
    // Setters
    // =========================

    /// @inheritdoc IPriceDifferenceCheckerLogicPancakeswap
    function pancakeswapChangeTokensAndFeePriceDiffChecker(
        IUniswapV3Pool pancakeswapPool,
        bytes32 pointer
    ) external onlyOwnerOrVaultItself {
        _changeTokensAndFeePriceDiffChecker(pancakeswapPool, pointer);
    }

    /// @inheritdoc IPriceDifferenceCheckerLogicPancakeswap
    function pancakeswapChangePercentageDeviationE3(
        uint24 percentageDeviation_E3,
        bytes32 pointer
    ) external onlyOwnerOrVaultItself {
        _changePercentageDeviationE3(percentageDeviation_E3, pointer);
    }

    // =========================
    // Getters
    // =========================

    /// @inheritdoc IPriceDifferenceCheckerLogicPancakeswap
    function pancakeswapGetLocalPriceDifferenceCheckerStorage(
        bytes32 pointer
    )
        external
        view
        returns (
            address token0,
            address token1,
            uint24 fee,
            uint24 percentageDeviation_E3,
            uint256 lastCheckPrice,
            bool initialized
        )
    {
        PriceDifferenceCheckerStorage storage pdcs = _getStorageUnsafe(pointer);

        return (
            pdcs.token0,
            pdcs.token1,
            pdcs.fee,
            pdcs.percentageDeviation_E3,
            pdcs.lastCheckPrice,
            pdcs.initialized
        );
    }
}
