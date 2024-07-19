// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import {IDexCheckerLogicPancakeswap} from "../../interfaces/checkers/IDexCheckerLogicPancakeswap.sol";

import {DexCheckerLogicBase} from "./DexCheckerLogicBase.sol";

/// @title DexCheckerLogicPancakeswap
contract DexCheckerLogicPancakeswap is
    IDexCheckerLogicPancakeswap,
    DexCheckerLogicBase
{
    // =========================
    // Constructor
    // =========================

    constructor(
        IUniswapV3Factory _pancakeswapFactory,
        INonfungiblePositionManager _pancakeswapNftPositionManager
    )
        DexCheckerLogicBase(_pancakeswapFactory, _pancakeswapNftPositionManager)
    {}

    // =========================
    // Initializer
    // =========================

    /// @inheritdoc IDexCheckerLogicPancakeswap
    function pancakeswapDexCheckerInitialize(
        uint256 nftId,
        bytes32 pointer
    ) external onlyVaultItself {
        _dexCheckerInitialize(nftId, pointer);
    }

    // =========================
    // Main functions
    // =========================

    /// @inheritdoc IDexCheckerLogicPancakeswap
    function pancakeswapCheckOutOfTickRange(
        bytes32 pointer
    ) external view returns (bool) {
        (
            int24 lowerTick,
            int24 upperTick,
            int24 currentTick
        ) = _getTickRangeAndCurrentTick(pointer);

        return (currentTick < lowerTick || currentTick > upperTick);
    }

    /// @inheritdoc IDexCheckerLogicPancakeswap
    function pancakeswapCheckInTickRange(
        bytes32 pointer
    ) external view returns (bool) {
        (
            int24 lowerTick,
            int24 upperTick,
            int24 currentTick
        ) = _getTickRangeAndCurrentTick(pointer);

        return (currentTick >= lowerTick && currentTick <= upperTick);
    }

    /// @inheritdoc IDexCheckerLogicPancakeswap
    function pancakeswapCheckFeesExistence(
        bytes32 pointer
    ) external view returns (bool) {
        return _checkFeesExistence(pointer);
    }

    // =========================
    // Getter
    // =========================

    /// @inheritdoc IDexCheckerLogicPancakeswap
    function pancakeswapGetLocalDexCheckerStorage(
        bytes32 pointer
    ) external view returns (uint256 nftId) {
        return _getStorageUnsafe(pointer).nftId;
    }
}
