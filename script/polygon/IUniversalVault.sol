// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// vault
import {IVault} from "../../src/vault/interfaces/IVault.sol";
import {IEventsAndErrors} from "../../src/vault/interfaces/IEventsAndErrors.sol";

import {IAccountAbstractionLogic} from "../../src/vault/interfaces/IAccountAbstractionLogic.sol";

// common methods
import {IVersionUpgradeLogic} from "../../src/vault/interfaces/IVersionUpgradeLogic.sol";
import {IAccessControlLogic} from "../../src/vault/interfaces/IAccessControlLogic.sol";
import {IEntryPointLogic} from "../../src/vault/interfaces/IEntryPointLogic.sol";
import {IExecutionLogic} from "../../src/vault/interfaces/IExecutionLogic.sol";
import {IVaultLogic} from "../../src/vault/interfaces/IVaultLogic.sol";
import {INativeWrapper} from "../../src/vault/interfaces/ourLogic/helpers/INativeWrapper.sol";

// dex methods
import {IDexBaseLogic} from "../../src/vault/interfaces/ourLogic/dexAutomation/IDexBaseLogic.sol";
import {IUniswapLogic} from "../../src/vault/interfaces/ourLogic/dexAutomation/IUniswapLogic.sol";

// aave methods
import {IAaveActionLogic} from "../../src/vault/interfaces/ourLogic/IAaveActionLogic.sol";
import {IDeltaNeutralStrategyLogic} from "../../src/vault/interfaces/ourLogic/IDeltaNeutralStrategyLogic.sol";

// checkers
import {IAaveCheckerLogic} from "../../src/vault/interfaces/checkers/IAaveCheckerLogic.sol";
import {IPriceCheckerLogicUniswap} from "../../src/vault/interfaces/checkers/IPriceCheckerLogicUniswap.sol";
import {IPriceDifferenceCheckerLogicUniswap} from "../../src/vault/interfaces/checkers/IPriceDifferenceCheckerLogicUniswap.sol";
import {ITimeCheckerLogic} from "../../src/vault/interfaces/checkers/ITimeCheckerLogic.sol";
import {IDexCheckerLogicUniswap} from "../../src/vault/interfaces/checkers/IDexCheckerLogicUniswap.sol";

// bridges
import {IStargateLogic} from "../../src/vault/interfaces/ourLogic/bridges/IStargateLogic.sol";
import {ILayerZeroLogic} from "../../src/vault/interfaces/ourLogic/bridges/ILayerZeroLogic.sol";
import {ICelerCircleBridgeLogic} from "../../src/vault/interfaces/ourLogic/bridges/ICelerCircleBridgeLogic.sol";

interface IUniversalVault is
    IVault,
    IEventsAndErrors,
    IVersionUpgradeLogic,
    IAccountAbstractionLogic,
    IAccessControlLogic,
    IEntryPointLogic,
    IExecutionLogic,
    IVaultLogic,
    INativeWrapper,
    IDexBaseLogic,
    IUniswapLogic,
    IAaveActionLogic,
    IDeltaNeutralStrategyLogic,
    IAaveCheckerLogic,
    IPriceCheckerLogicUniswap,
    IPriceDifferenceCheckerLogicUniswap,
    ITimeCheckerLogic,
    IStargateLogic,
    ILayerZeroLogic,
    ICelerCircleBridgeLogic,
    IDexCheckerLogicUniswap
{}
