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
import {VaultLogic} from "../../../src/vault/logics/VaultLogic.sol";

import {TransferHelper} from "../../../src/vault/libraries/utils/TransferHelper.sol";

import {DeltaNeutralStrategyBase, Registry, IERC20Metadata, VaultProxyAdmin} from "./DeltaNeutralStrategyBase.t.sol";

contract TestDeltaNeutralStrategyWETHUSDC is DeltaNeutralStrategyBase {
    // mainnet USDC
    address usdcAddress = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    // mainnet WETH
    address wethAddress = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    IUniswapV3Pool pool;
    uint24 poolFee;

    uint256 nftId;

    function setUp() public {
        vm.createSelectFork(vm.envString("ARB_RPC_URL"));

        vm.deal(vaultOwner, 10 ether);
        vm.deal(user, 10 ether);

        donor = 0x3e0199792Ce69DC29A0a36146bFa68bd7C8D6633; // wallet for token airdrop

        vm.startPrank(donor);
        TransferHelper.safeTransfer(usdcAddress, address(vaultOwner), 1000e6);

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
            reg.uniswapFactory.getPool(usdcAddress, wethAddress, 3000)
        );
        poolFee = pool.fee();

        address vaultProxy = vaultFactory.deploy(1, 1);
        vm.deal(vaultProxy, 10 ether);

        TransferHelper.safeTransfer(usdcAddress, vaultProxy, 300e6);

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
        _mParams.token1 = usdcAddress;
        _mParams.fee = poolFee;
        _mParams.tickLower = ((currentTick - 4000) / 60) * 60;
        _mParams.tickUpper = ((currentTick + 4000) / 60) * 60;
        _mParams.amount0Desired = 0.001e18;
        _mParams.amount1Desired = 1e6;
        _mParams.recipient = vaultOwner;
        _mParams.deadline = block.timestamp;

        vm.prank(vaultOwner);
        TransferHelper.safeApprove(
            usdcAddress,
            address(reg.uniswapNFTPositionManager),
            type(uint256).max
        );

        vm.prank(vaultOwner);
        TransferHelper.safeApprove(
            wethAddress,
            address(reg.uniswapNFTPositionManager),
            type(uint256).max
        );

        // mint new nft for tests
        vm.prank(vaultOwner);
        (nftId, , , ) = reg.uniswapNFTPositionManager.mint(_mParams);
        vm.prank(vaultOwner);
        reg.uniswapNFTPositionManager.safeTransferFrom(
            vaultOwner,
            vaultProxy,
            nftId
        );

        vm.prank(vaultOwner);
        TransferHelper.safeApprove(usdcAddress, vaultProxy, type(uint256).max);
        vm.prank(vaultOwner);
        TransferHelper.safeApprove(wethAddress, vaultProxy, type(uint256).max);
    }

    // =========================
    // Deposit
    // =========================

    function test_arb_deltaNeutralStrategy_depositETH_shouldEmitEvent_wethUsdc()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            usdcAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyDeposit();
        vault.depositETH(5e18, 0.1e18, storagePointerDeltaNeutral1);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);
    }

    function test_arb_deltaNeutralStrategy_deposit_shouldEmitEvent_usdcWeth()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            usdcAddress,
            wethAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral2
        );

        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyDeposit();
        vault.deposit(250e6, 0.1e18, storagePointerDeltaNeutral2);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral2
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);
    }

    // =========================
    // Withdraw
    // =========================

    function test_arb_deltaNeutralStrategy_withdraw_shouldEmitEvent_withdraw100Percents_wethUsdc()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            usdcAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vault.deposit(2e18, 0.01e18, storagePointerDeltaNeutral1);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);

        vm.warp(block.timestamp + 60);
        vm.roll(block.number + 5);

        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyWithdraw();
        vault.withdraw(1e18, 0.01e18, storagePointerDeltaNeutral1);

        (, currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertEq(currentHF, type(uint256).max);
    }

    function test_arb_deltaNeutralStrategy_withdraw_shouldEmitEvent_withdraw50Percents_wethUsdc()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            usdcAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vault.deposit(2e18, 0.01e18, storagePointerDeltaNeutral1);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);

        vm.warp(block.timestamp + 60);
        vm.roll(block.number + 5);

        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyWithdraw();
        vault.withdraw(0.5e18, 0.01e18, storagePointerDeltaNeutral1);

        (, currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);
    }

    function test_arb_deltaNeutralStrategy_withdraw_shouldEmitEvent_withdraw100Percents_usdcWeth()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            usdcAddress,
            wethAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral2
        );

        vm.prank(address(vault));
        vault.deposit(250e6, 0.01e18, storagePointerDeltaNeutral2);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral2
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);

        vm.warp(block.timestamp + 60);
        vm.roll(block.number + 5);

        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyWithdraw();
        vault.withdraw(1e18, 0.01e18, storagePointerDeltaNeutral2);

        (, currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral2
        );
        assertEq(currentHF, type(uint256).max);
    }

    function test_arb_deltaNeutralStrategy_withdraw_shouldEmitEvent_withdraw50Percents_usdcWeth()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            usdcAddress,
            wethAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral2
        );

        vm.prank(address(vault));
        vault.deposit(250e6, 0.01e18, storagePointerDeltaNeutral2);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral2
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);

        vm.warp(block.timestamp + 60);
        vm.roll(block.number + 5);

        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyWithdraw();
        vault.withdraw(0.5e18, 0.01e18, storagePointerDeltaNeutral2);

        (, currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral2
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);
    }

    // =========================
    // Rebalance
    // =========================

    function test_arb_deltaNeutralStrategy_rebalance_shouldEmitEvent_underHFRange_wethUsdc()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            usdcAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vault.deposit(2e18, 0.01e18, storagePointerDeltaNeutral1);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);

        vm.warp(block.timestamp + 120);
        vm.roll(block.number + 10);

        // lowering HF under range 1.6-1.8
        vm.prank(address(vault));
        AaveActionLogic(address(vault)).withdrawAaveAction(
            wethAddress,
            0.25e18
        );

        (, currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertLt(currentHF, 1.6e18);

        uint256 wmaticBalance = IERC20Metadata(wethAddress).balanceOf(
            address(vault)
        );
        vm.prank(address(vault));
        VaultLogic(payable(address(vault))).withdrawERC20(
            wethAddress,
            vaultOwner,
            wmaticBalance
        );

        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyRebalance();
        vault.rebalance(1e18, storagePointerDeltaNeutral1);

        (, currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);
    }

    function test_arb_deltaNeutralStrategy_rebalance_shouldEmitEvent_aboveHFRange_wethUsdc()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            usdcAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vault.deposit(2e18, 0.01e18, storagePointerDeltaNeutral1);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);

        vm.warp(block.timestamp + 120);
        vm.roll(block.number + 10);

        vm.prank(address(vault));
        IERC20Metadata(usdcAddress).transfer(address(vault), 250e6);

        // raising HF above range 1.6-1.8
        vm.prank(address(vault));
        AaveActionLogic(address(vault)).repayAaveAction(usdcAddress, 250e6);

        (, currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertGt(currentHF, 1.8e18);

        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyRebalance();
        vault.rebalance(1e18, storagePointerDeltaNeutral1);

        (, currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);
    }

    function test_arb_deltaNeutralStrategy_rebalance_shouldEmitEvent_underHFRange_usdcWeth()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            usdcAddress,
            wethAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral2
        );

        vm.prank(address(vault));
        vault.deposit(250e6, 0.01e18, storagePointerDeltaNeutral2);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral2
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);

        vm.warp(block.timestamp + 120);
        vm.roll(block.number + 10);

        // lowering HF under range 1.6-1.8
        vm.prank(address(vault));
        AaveActionLogic(address(vault)).withdrawAaveAction(usdcAddress, 50e6);

        (, currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral2
        );
        assertLt(currentHF, 1.6e18);

        uint256 usdcBalance = IERC20Metadata(usdcAddress).balanceOf(
            address(vault)
        );
        vm.prank(address(vault));
        VaultLogic(payable(address(vault))).withdrawERC20(
            usdcAddress,
            vaultOwner,
            usdcBalance
        );

        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyRebalance();
        vault.rebalance(1e18, storagePointerDeltaNeutral2);

        (, currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral2
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);
    }

    function test_arb_deltaNeutralStrategy_rebalance_shouldEmitEvent_aboveHFRange_usdcWeth()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            usdcAddress,
            wethAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral2
        );

        vm.prank(address(vault));
        vault.deposit(250e6, 0.01e18, storagePointerDeltaNeutral2);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral2
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);

        vm.warp(block.timestamp + 120);
        vm.roll(block.number + 10);

        uint256 totalDebt = reg.lens.aaveLogicLens.getTotalDebt(
            wethAddress,
            address(vault)
        );

        vm.prank(address(vault));
        IERC20Metadata(wethAddress).transfer(address(vault), totalDebt >> 2);

        // raising HF above range 1.6-1.8
        vm.prank(address(vault));
        AaveActionLogic(address(vault)).repayAaveAction(
            wethAddress,
            totalDebt >> 2
        );

        (, currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral2
        );
        assertGt(currentHF, 1.8e18);

        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyRebalance();
        vault.rebalance(1e18, storagePointerDeltaNeutral2);

        (, currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral2
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);
    }
}
