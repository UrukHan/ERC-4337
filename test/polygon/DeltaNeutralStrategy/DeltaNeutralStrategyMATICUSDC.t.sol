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

contract TestDeltaNeutralStrategyMATICUSDC is DeltaNeutralStrategyBase {
    // mainnet USDC
    address usdcAddress = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    // mainnet WMATIC
    address wmaticAddress = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

    IUniswapV3Pool pool =
        IUniswapV3Pool(0x88f3C15523544835fF6c738DDb30995339AD57d6);
    uint24 poolFee;

    uint256 nftId;

    function setUp() public {
        vm.createSelectFork(vm.envString("POL_RPC_URL"));

        poolFee = pool.fee();

        vm.deal(vaultOwner, 10 ether);
        vm.deal(user, 10 ether);

        donor = 0xA374094527e1673A86dE625aa59517c5dE346d32; // wallet for token airdrop

        vm.startPrank(donor);
        TransferHelper.safeTransfer(usdcAddress, address(vaultOwner), 600e6);
        TransferHelper.safeTransfer(wmaticAddress, address(vaultOwner), 500e18);
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
        vm.deal(vaultProxy, 200 ether);

        TransferHelper.safeTransfer(usdcAddress, vaultProxy, 300e6);

        TransferHelper.safeTransfer(wmaticAddress, vaultProxy, 250e18);

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
            wmaticAddress,
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
        TransferHelper.safeApprove(
            wmaticAddress,
            vaultProxy,
            type(uint256).max
        );
    }

    // =========================
    // Deposit
    // =========================

    function test_polygon_deltaNeutralStrategy_depositETH_shouldEmitEvent_maticUsdc()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wmaticAddress,
            usdcAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyDeposit();
        vault.depositETH(200e18, 0.1e18, storagePointerDeltaNeutral1);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);
    }

    function test_polygon_deltaNeutralStrategy_deposit_shouldEmitEvent_usdcMatic()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            usdcAddress,
            wmaticAddress,
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

    function test_polygon_deltaNeutralStrategy_withdraw_shouldEmitEvent_withdraw100Percents_maticUsdc()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wmaticAddress,
            usdcAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vault.deposit(50e18, 0.01e18, storagePointerDeltaNeutral1);

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

    function test_polygon_deltaNeutralStrategy_withdraw_shouldEmitEvent_withdraw50Percents_maticUsdc()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wmaticAddress,
            usdcAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vault.deposit(50e18, 0.01e18, storagePointerDeltaNeutral1);

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

    function test_polygon_deltaNeutralStrategy_withdraw_shouldEmitEvent_withdraw100Percents_usdcMatic()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            usdcAddress,
            wmaticAddress,
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

    function test_polygon_deltaNeutralStrategy_withdraw_shouldEmitEvent_withdraw50Percents_usdcMatic()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            usdcAddress,
            wmaticAddress,
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

    function test_polygon_deltaNeutralStrategy_rebalance_shouldEmitEvent_underHFRange_maticUsdc()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wmaticAddress,
            usdcAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vault.deposit(50e18, 0.01e18, storagePointerDeltaNeutral1);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);

        vm.warp(block.timestamp + 120);
        vm.roll(block.number + 10);

        // lowering HF under range 1.6-1.8
        vm.prank(address(vault));
        AaveActionLogic(address(vault)).withdrawAaveAction(
            wmaticAddress,
            10e18
        );

        (, currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertLt(currentHF, 1.6e18);

        uint256 wmaticBalance = IERC20Metadata(wmaticAddress).balanceOf(
            address(vault)
        );
        vm.prank(vaultOwner);
        VaultLogic(payable(address(vault))).withdrawERC20(
            wmaticAddress,
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

    function test_polygon_deltaNeutralStrategy_rebalance_shouldEmitEvent_aboveHFRange_maticUsdc()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wmaticAddress,
            usdcAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vault.deposit(75e18, 0.01e18, storagePointerDeltaNeutral1);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);

        vm.warp(block.timestamp + 120);
        vm.roll(block.number + 10);

        vm.prank(vaultOwner);
        IERC20Metadata(usdcAddress).transfer(address(vault), 5e6);

        // raising HF above range 1.6-1.8
        vm.prank(address(vault));
        AaveActionLogic(address(vault)).repayAaveAction(usdcAddress, 5e6);

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

    function test_polygon_deltaNeutralStrategy_rebalance_shouldEmitEvent_underHFRange_usdcMatic()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            usdcAddress,
            wmaticAddress,
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
        vm.prank(vaultOwner);
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

    function test_polygon_deltaNeutralStrategy_rebalance_shouldEmitEvent_aboveHFRange_usdcMatic()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            usdcAddress,
            wmaticAddress,
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

        vm.prank(vaultOwner);
        IERC20Metadata(wmaticAddress).transfer(address(vault), 50e18);

        // raising HF above range 1.6-1.8
        vm.prank(address(vault));
        AaveActionLogic(address(vault)).repayAaveAction(wmaticAddress, 50e18);

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
