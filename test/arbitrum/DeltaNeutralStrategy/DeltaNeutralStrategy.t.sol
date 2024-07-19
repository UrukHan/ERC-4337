// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IPool} from "@aave/aave-v3-core/contracts/interfaces/IPool.sol";

import {AccessControlLogic} from "../../../src/vault/logics/AccessControlLogic.sol";
import {BaseContract, Constants} from "../../../src/vault/libraries/BaseContract.sol";
import {DeltaNeutralStrategyLogic} from "../../../src/vault/logics/OurLogic/DeltaNeutralStrategyLogic.sol";
import {AaveActionLogic} from "../../../src/vault/logics/OurLogic/AaveActionLogic.sol";
import {AaveCheckerLogic} from "../../../src/vault/logics/Checkers/AaveCheckerLogic.sol";

import {TransferHelper} from "../../../src/vault/libraries/utils/TransferHelper.sol";
import {VaultLogic} from "../../../src/vault/logics/VaultLogic.sol";

import {DeltaNeutralStrategyBase, Registry, VaultProxyAdmin} from "./DeltaNeutralStrategyBase.t.sol";

contract TestDeltaNeutralStrategy is DeltaNeutralStrategyBase {
    // mainnet USDT
    address usdtAddress = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    // mainnet WETH
    address wethAddress = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    IUniswapV3Pool pool;
    uint24 poolFee;

    uint256 nftIdAboveCurrentTick;
    uint256 nftIdBelowCurrentTick;

    function setUp() public {
        vm.createSelectFork(vm.envString("ARB_RPC_URL"));

        vm.deal(vaultOwner, 10 ether);
        vm.deal(user, 10 ether);

        donor = 0x3e0199792Ce69DC29A0a36146bFa68bd7C8D6633; // wallet for token airdrop

        vm.startPrank(donor);
        TransferHelper.safeTransfer(usdtAddress, address(vaultOwner), 3000e6);
        TransferHelper.safeTransfer(wethAddress, address(vaultOwner), 10e18);
        vm.stopPrank();

        vm.startPrank(vaultOwner);
        reg = deploySystemContracts(
            isTest,
            Registry.contractsByChainId(block.chainid)
        );

        uint256 nonce = vm.getNonce(vaultOwner);
        reg.vaultProxyAdmin = new VaultProxyAdmin(
            vm.computeCreateAddress(vaultOwner, nonce + 3)
        );

        (vaultFactory, ) = addImplementation(reg, isTest, vaultOwner);

        pool = IUniswapV3Pool(
            reg.uniswapFactory.getPool(usdtAddress, wethAddress, 3000)
        );
        poolFee = pool.fee();

        address vaultProxy = vaultFactory.deploy(1, 1);

        TransferHelper.safeTransfer(usdtAddress, vaultProxy, 1500e6);
        TransferHelper.safeTransfer(wethAddress, vaultProxy, 5e18);

        vm.stopPrank();

        vm.prank(vaultProxy);
        // init aave checker
        AaveCheckerLogic(vaultProxy).aaveCheckerInitialize(
            1.6e18,
            1.8e18,
            vaultProxy,
            storagePointerAaveChecker
        );

        vm.prank(vaultProxy);
        AccessControlLogic(vaultProxy).grantRole(
            Constants.EXECUTOR_ROLE,
            executor
        );

        vault = DeltaNeutralStrategyLogic(vaultProxy);

        (, int24 currentTick, , , , , ) = pool.slot0();
        INonfungiblePositionManager.MintParams memory _mParams;
        _mParams.token0 = wethAddress;
        _mParams.token1 = usdtAddress;
        _mParams.fee = pool.fee();
        _mParams.tickLower = ((currentTick + 120) / 60) * 60;
        _mParams.tickUpper = ((currentTick + 4000) / 60) * 60;
        _mParams.amount0Desired = 0.01e18;
        _mParams.amount1Desired = 1e6;
        _mParams.recipient = vaultOwner;
        _mParams.deadline = block.timestamp;

        vm.prank(vaultOwner);
        TransferHelper.safeApprove(
            wethAddress,
            address(reg.uniswapNFTPositionManager),
            type(uint256).max
        );

        vm.prank(vaultOwner);
        TransferHelper.safeApprove(
            usdtAddress,
            address(reg.uniswapNFTPositionManager),
            type(uint256).max
        );

        // mint new nft for tests
        vm.prank(vaultOwner);
        (nftIdAboveCurrentTick, , , ) = reg.uniswapNFTPositionManager.mint(
            _mParams
        );
        vm.prank(vaultOwner);
        reg.uniswapNFTPositionManager.safeTransferFrom(
            vaultOwner,
            vaultProxy,
            nftIdAboveCurrentTick
        );

        _mParams.tickLower = ((currentTick - 4000) / 60) * 60;
        _mParams.tickUpper = ((currentTick - 120) / 60) * 60;

        // mint new nft for tests
        vm.prank(vaultOwner);
        (nftIdBelowCurrentTick, , , ) = reg.uniswapNFTPositionManager.mint(
            _mParams
        );
        vm.prank(vaultOwner);
        reg.uniswapNFTPositionManager.safeTransferFrom(
            vaultOwner,
            vaultProxy,
            nftIdBelowCurrentTick
        );

        vm.prank(vaultOwner);
        TransferHelper.safeApprove(wethAddress, vaultProxy, type(uint256).max);
        vm.prank(vaultOwner);
        TransferHelper.safeApprove(usdtAddress, vaultProxy, type(uint256).max);
    }

    // =========================
    // Above current tick
    // =========================

    function test_arb_deltaNeutralStrategy_aboveCurrentTick() external {
        vm.prank(address(vault));
        vault.initialize(
            nftIdAboveCurrentTick,
            1.7e18,
            wethAddress,
            usdtAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        // Nothing added to aave
        vm.expectEmit();
        emit DeltaNeutralStrategyDeposit();
        vault.deposit(2e18, 0.1e18, storagePointerDeltaNeutral1);

        (, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertEq(currentHF, type(uint256).max);
        assertEq(
            reg.lens.aaveLogicLens.getSupplyAmount(wethAddress, address(vault)),
            0
        );
        assertEq(
            reg.lens.aaveLogicLens.getTotalDebt(usdtAddress, address(vault)),
            0
        );

        // Nothing withdrawed from aave (no debt and supply)
        uint256 balanceBefore = TransferHelper.safeGetBalance(
            wethAddress,
            vaultOwner
        );

        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyWithdraw();
        vault.withdraw(1e18, 0.1e18, storagePointerDeltaNeutral1);

        uint256 balanceAfter = TransferHelper.safeGetBalance(
            wethAddress,
            vaultOwner
        );
        assertEq(balanceAfter, balanceBefore);

        // rebalance do nothing
        (, currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertEq(currentHF, type(uint256).max);

        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyRebalance();
        vault.rebalance(1e18, storagePointerDeltaNeutral1);

        (, currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertEq(currentHF, type(uint256).max);
    }

    // =========================
    // Below current tick
    // =========================

    function test_arb_deltaNeutralStrategy_belowCurrentTick() external {
        vm.prank(address(vault));
        vault.initialize(
            nftIdBelowCurrentTick,
            1.7e18,
            wethAddress,
            usdtAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        // correctly deposit
        vm.expectEmit();
        emit DeltaNeutralStrategyDeposit();
        vault.deposit(2e18, 0.1e18, storagePointerDeltaNeutral1);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertApproxEqAbs(currentHF, targetHF, 0.04e18);

        // correctly withdraw half
        uint256 supplyBefore = reg.lens.aaveLogicLens.getSupplyAmount(
            wethAddress,
            address(vault)
        );
        uint256 debtBefore = reg.lens.aaveLogicLens.getTotalDebt(
            usdtAddress,
            address(vault)
        );

        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyWithdraw();
        vault.withdraw(0.5e18, 0.1e18, storagePointerDeltaNeutral1);

        uint256 supplyAfter = reg.lens.aaveLogicLens.getSupplyAmount(
            wethAddress,
            address(vault)
        );
        uint256 debtAfter = reg.lens.aaveLogicLens.getTotalDebt(
            usdtAddress,
            address(vault)
        );

        assertApproxEqAbs(supplyAfter, supplyBefore >> 1, 0.04e18);
        assertApproxEqAbs(debtAfter, debtBefore >> 1, 3e6);

        vm.warp(block.timestamp + 120);
        vm.roll(block.number + 10);

        vm.prank(vaultOwner);
        TransferHelper.safeTransfer(usdtAddress, address(vault), 100e6);

        // raising HF above range 1.6-1.8

        vm.prank(address(vault));
        AaveActionLogic(address(vault)).repayAaveAction(usdtAddress, 100e6);

        (, currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertGt(currentHF, 1.8e18);

        vm.prank(address(vault));
        // correctly rebalance
        vm.expectEmit();
        emit DeltaNeutralStrategyRebalance();
        vault.rebalance(1e18, storagePointerDeltaNeutral1);

        (, currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertApproxEqAbs(currentHF, targetHF, 0.04e18);
    }
}
