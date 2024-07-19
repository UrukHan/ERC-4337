// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IPool} from "@aave/aave-v3-core/contracts/interfaces/IPool.sol";
import {IVariableDebtToken} from "@aave/aave-v3-core/contracts/interfaces/IVariableDebtToken.sol";
import {IAToken} from "@aave/aave-v3-core/contracts/interfaces/IAToken.sol";
import {IPoolDataProvider} from "@aave/aave-v3-core/contracts/interfaces/IPoolDataProvider.sol";
import {IPoolAddressesProvider} from "@aave/aave-v3-core/contracts/interfaces/IPoolAddressesProvider.sol";

import {AaveLogicLib} from "../vault/libraries/AaveLogicLib.sol";

import {IAaveLogicLens} from "./IAaveLogicLens.sol";

/// @title AaveLogicLens
/// @notice A lens contract to extract information from Aave V3
/// @dev This contract interacts with Aave V3 and provides helper methods for fetching user-specific data
contract AaveLogicLens is IAaveLogicLens {
    // =========================
    // Constructor
    // =========================

    IPoolAddressesProvider private immutable poolAddressesProvider;

    constructor(IPoolAddressesProvider _poolAddressesProvider) {
        poolAddressesProvider = _poolAddressesProvider;
    }

    // =========================
    // View Functions
    // =========================

    /// @inheritdoc IAaveLogicLens
    function getSupplyAmount(
        address supplyToken,
        address user
    ) external view returns (uint256) {
        address aSupplyToken = AaveLogicLib.aSupplyTokenAddress(
            supplyToken,
            IPool(poolAddressesProvider.getPool())
        );
        return AaveLogicLib.getSupplyAmount(aSupplyToken, user);
    }

    /// @inheritdoc IAaveLogicLens
    function getTotalDebt(
        address debtToken,
        address user
    ) external view returns (uint256) {
        address aDebtToken = AaveLogicLib.aDebtTokenAddress(
            debtToken,
            IPool(poolAddressesProvider.getPool())
        );
        return AaveLogicLib.getTotalDebt(aDebtToken, user);
    }

    /// @inheritdoc IAaveLogicLens
    function getCurrentHF(
        address user
    ) external view returns (uint256 currentHF) {
        return AaveLogicLib.getCurrentHF(user, poolAddressesProvider);
    }

    /// @inheritdoc IAaveLogicLens
    function getCurrentLiquidationThreshold(
        address token
    ) external view returns (uint256 currentLiquidationThreshold_1e4) {
        return
            AaveLogicLib.getCurrentLiquidationThreshold(
                token,
                poolAddressesProvider
            );
    }
}
