// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {FullDeploy, VaultProxyAdmin, Registry} from "../../../script/FullDeploy.s.sol";

import {VaultFactory} from "../../../src/VaultFactory.sol";
import {DeltaNeutralStrategyLogic} from "../../../src/vault/logics/OurLogic/DeltaNeutralStrategyLogic.sol";

contract DeltaNeutralStrategyBase is Test, FullDeploy {
    bool isTest = true;

    // =========================
    // Events
    // =========================

    event DeltaNeutralStrategyDeposit();
    event DeltaNeutralStrategyWithdraw();
    event DeltaNeutralStrategyRebalance();
    event DeltaNeutralStrategyInitialize();
    event DeltaNeutralStrategyNewHealthFactor(uint256 newTargetHealthFactor);

    Registry.Contracts reg;

    VaultFactory vaultFactory;
    DeltaNeutralStrategyLogic vault;

    address donor;
    address vaultOwner = makeAddr("VAULT_OWNER");
    address executor = makeAddr("EXECUTOR");
    address user = makeAddr("USER");

    bytes32 internal immutable storagePointerAaveChecker =
        keccak256("vault.standard.test.storageAaveChecker");
    bytes32 internal immutable storagePointerDeltaNeutral1 =
        keccak256("vault.standard.test.storageDeltaNeutral1");
    bytes32 internal immutable storagePointerDeltaNeutral2 =
        keccak256("vault.standard.test.storageDeltaNeutral2");
}
