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
import {IPancakeswapLogic} from "../../src/vault/interfaces/ourLogic/dexAutomation/IPancakeswapLogic.sol";

// checkers
import {IPriceCheckerLogicPancakeswap} from "../../src/vault/interfaces/checkers/IPriceCheckerLogicPancakeswap.sol";
import {IPriceCheckerLogicUniswap} from "../../src/vault/interfaces/checkers/IPriceCheckerLogicUniswap.sol";
import {IPriceDifferenceCheckerLogicPancakeswap} from "../../src/vault/interfaces/checkers/IPriceDifferenceCheckerLogicPancakeswap.sol";
import {IPriceDifferenceCheckerLogicUniswap} from "../../src/vault/interfaces/checkers/IPriceDifferenceCheckerLogicUniswap.sol";
import {ITimeCheckerLogic} from "../../src/vault/interfaces/checkers/ITimeCheckerLogic.sol";
import {IDexCheckerLogicPancakeswap} from "../../src/vault/interfaces/checkers/IDexCheckerLogicPancakeswap.sol";
import {IDexCheckerLogicUniswap} from "../../src/vault/interfaces/checkers/IDexCheckerLogicUniswap.sol";

// bridges
import {IStargateLogic} from "../../src/vault/interfaces/ourLogic/bridges/IStargateLogic.sol";
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
    INativeWrapper,
    IDexBaseLogic,
    IPancakeswapLogic,
    IUniswapLogic,
    IPriceCheckerLogicPancakeswap,
    IPriceCheckerLogicUniswap,
    IPriceDifferenceCheckerLogicPancakeswap,
    IPriceDifferenceCheckerLogicUniswap,
    ITimeCheckerLogic,
    IStargateLogic,
    ILayerZeroLogic,
    IDexCheckerLogicPancakeswap,
    IDexCheckerLogicUniswap
{}
