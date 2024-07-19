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

// dex methods
import {IDexBaseLogic} from "../../src/vault/interfaces/ourLogic/dexAutomation/IDexBaseLogic.sol";
import {IUniswapLogic} from "../../src/vault/interfaces/ourLogic/dexAutomation/IUniswapLogic.sol";

// checkers
import {IPriceCheckerLogicUniswap} from "../../src/vault/interfaces/checkers/IPriceCheckerLogicUniswap.sol";
import {IPriceDifferenceCheckerLogicUniswap} from "../../src/vault/interfaces/checkers/IPriceDifferenceCheckerLogicUniswap.sol";
import {ITimeCheckerLogic} from "../../src/vault/interfaces/checkers/ITimeCheckerLogic.sol";
import {IDexCheckerLogicUniswap} from "../../src/vault/interfaces/checkers/IDexCheckerLogicUniswap.sol";

// bridges
import {ILayerZeroLogic} from "../../src/vault/interfaces/ourLogic/bridges/ILayerZeroLogic.sol";

interface IUniversalVault is
    IVault,
    IEventsAndErrors,
    IVersionUpgradeLogic,
    IAccountAbstractionLogic,
    IAccessControlLogic,
    IEntryPointLogic,
    IExecutionLogic,
    IVaultLogic,
    IDexBaseLogic,
    IUniswapLogic,
    IPriceCheckerLogicUniswap,
    IPriceDifferenceCheckerLogicUniswap,
    ITimeCheckerLogic,
    ILayerZeroLogic,
    IDexCheckerLogicUniswap
{}
