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

import {DeltaNeutralStrategyBase, Registry, IERC20Metadata, VaultProxyAdmin} from "./DeltaNeutralStrategyBase.t.sol";

contract TestDeltaNeutralStrategy is DeltaNeutralStrategyBase {
    // mainnet USDC
    address usdcAddress = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    // mainnet WMATIC
    address wmaticAddress = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

    IUniswapV3Pool pool =
        IUniswapV3Pool(0x88f3C15523544835fF6c738DDb30995339AD57d6);
    uint24 poolFee;

    uint256 nftIdAboveCurrentTick;
    uint256 nftIdBelowCurrentTick;

    function setUp() public {
        vm.createSelectFork(vm.envString("POL_RPC_URL"));

        poolFee = pool.fee();

        vm.deal(vaultOwner, 10 ether);
        vm.deal(user, 10 ether);

        donor = 0xA374094527e1673A86dE625aa59517c5dE346d32; // wallet for token airdrop

        vm.startPrank(donor);
        TransferHelper.safeTransfer(usdcAddress, address(vaultOwner), 3000e6);
        TransferHelper.safeTransfer(
            wmaticAddress,
            address(vaultOwner),
            1000e18
        );
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

        address vaultProxy = vaultFactory.deploy(1, 1);

        TransferHelper.safeTransfer(usdcAddress, vaultProxy, 1500e6);

        TransferHelper.safeTransfer(wmaticAddress, vaultProxy, 500e18);

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
        _mParams.token0 = wmaticAddress;
        _mParams.token1 = usdcAddress;
        _mParams.fee = poolFee;
        _mParams.tickLower = ((currentTick + 120) / 60) * 60;
        _mParams.tickUpper = ((currentTick + 4000) / 60) * 60;
        _mParams.amount0Desired = 0.01e18;
        _mParams.amount1Desired = 1e6;
        _mParams.recipient = vaultOwner;
        _mParams.deadline = block.timestamp;

        vm.prank(vaultOwner);
        TransferHelper.safeApprove(
            wmaticAddress,
            address(reg.uniswapNFTPositionManager),
            type(uint256).max
        );
        vm.prank(vaultOwner);
        TransferHelper.safeApprove(
            usdcAddress,
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
        TransferHelper.safeApprove(
            wmaticAddress,
            vaultProxy,
            type(uint256).max
        );
        vm.prank(vaultOwner);
        TransferHelper.safeApprove(usdcAddress, vaultProxy, type(uint256).max);
    }

    // =========================
    // Above current tick
    // =========================

    function test_polygon_deltaNeutralStrategy_aboveCurrentTick() external {
        vm.prank(address(vault));
        vault.initialize(
            nftIdAboveCurrentTick,
            1.7e18,
            wmaticAddress,
            usdcAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        // Nothing added to aave
        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyDeposit();
        vault.deposit(50e18, 0.1e18, storagePointerDeltaNeutral1);

        (, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertEq(currentHF, type(uint256).max);
        assertEq(
            reg.lens.aaveLogicLens.getSupplyAmount(
                wmaticAddress,
                address(vault)
            ),
            0
        );
        assertEq(
            reg.lens.aaveLogicLens.getTotalDebt(usdcAddress, address(vault)),
            0
        );

        // Nothing withdrawed from aave (no debt and supply)
        uint256 balanceBefore = IERC20Metadata(wmaticAddress).balanceOf(
            vaultOwner
        );

        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyWithdraw();
        vault.withdraw(1e18, 0.1e18, storagePointerDeltaNeutral1);

        uint256 balanceAfter = IERC20Metadata(wmaticAddress).balanceOf(
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

    function test_polygon_deltaNeutralStrategy_belowCurrentTick() external {
        vm.prank(address(vault));
        vault.initialize(
            nftIdBelowCurrentTick,
            1.7e18,
            wmaticAddress,
            usdcAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        // correctly deposit
        vm.expectEmit();
        emit DeltaNeutralStrategyDeposit();
        vault.deposit(50e18, 0.1e18, storagePointerDeltaNeutral1);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);

        // correctly withdraw half
        uint256 supplyBefore = reg.lens.aaveLogicLens.getSupplyAmount(
            wmaticAddress,
            address(vault)
        );
        uint256 debtBefore = reg.lens.aaveLogicLens.getTotalDebt(
            usdcAddress,
            address(vault)
        );

        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyWithdraw();
        vault.withdraw(0.5e18, 0.1e18, storagePointerDeltaNeutral1);

        uint256 supplyAfter = reg.lens.aaveLogicLens.getSupplyAmount(
            wmaticAddress,
            address(vault)
        );
        uint256 debtAfter = reg.lens.aaveLogicLens.getTotalDebt(
            usdcAddress,
            address(vault)
        );

        assertApproxEqAbs(supplyAfter, supplyBefore >> 1, 0.01e18);
        assertApproxEqAbs(debtAfter, debtBefore >> 1, 0.1e6);

        vm.warp(block.timestamp + 120);
        vm.roll(block.number + 10);

        vm.prank(vaultOwner);
        IERC20Metadata(usdcAddress).transfer(address(vault), 10e6);

        // raising HF above range 1.6-1.8
        vm.prank(address(vault));
        AaveActionLogic(address(vault)).repayAaveAction(usdcAddress, 10e6);

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
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);
    }
}
