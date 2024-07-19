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

contract TestDeltaNeutralStrategyWBTCWETH is DeltaNeutralStrategyBase {
    // mainnet WETH
    address wethAddress = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    // mainnet WBTC
    address wbtcAddress = 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6;

    IUniswapV3Pool pool =
        IUniswapV3Pool(0x50eaEDB835021E4A108B7290636d62E9765cc6d7);
    uint24 poolFee;

    uint256 nftId;

    function setUp() public {
        vm.createSelectFork(vm.envString("POL_RPC_URL"));

        poolFee = pool.fee();

        vm.deal(vaultOwner, 10 ether);
        vm.deal(user, 10 ether);

        donor = 0xfe343675878100b344802A6763fd373fDeed07A4; // wallet for token airdrop

        vm.startPrank(donor);
        TransferHelper.safeTransfer(wbtcAddress, address(vaultOwner), 1.5e8);
        TransferHelper.safeTransfer(wethAddress, address(vaultOwner), 200e18);
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

        TransferHelper.safeTransfer(wbtcAddress, vaultProxy, 0.9e8);

        TransferHelper.safeTransfer(wethAddress, vaultProxy, 80e18);

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
        _mParams.token0 = wbtcAddress;
        _mParams.token1 = wethAddress;
        _mParams.fee = poolFee;
        _mParams.tickLower = ((currentTick - 4000) / 60) * 60;
        _mParams.tickUpper = ((currentTick + 4000) / 60) * 60;
        _mParams.amount0Desired = 0.001e18;
        _mParams.amount1Desired = 1e6;
        _mParams.recipient = vaultOwner;
        _mParams.deadline = block.timestamp;

        vm.prank(vaultOwner);
        TransferHelper.safeApprove(
            wbtcAddress,
            address(reg.uniswapNFTPositionManager),
            type(uint256).max
        );
        vm.prank(vaultOwner);
        TransferHelper.safeApprove(
            wethAddress,
            address(reg.uniswapNFTPositionManager),
            type(uint256).max
        );

        vm.prank(vaultOwner);
        // mint new nft for tests
        (nftId, , , ) = reg.uniswapNFTPositionManager.mint(_mParams);
        vm.prank(vaultOwner);
        reg.uniswapNFTPositionManager.safeTransferFrom(
            vaultOwner,
            vaultProxy,
            nftId
        );

        vm.prank(vaultOwner);
        TransferHelper.safeApprove(wethAddress, vaultProxy, type(uint256).max);
        vm.prank(vaultOwner);
        TransferHelper.safeApprove(wbtcAddress, vaultProxy, type(uint256).max);
    }

    // =========================
    // Deposit
    // =========================

    function test_polygon_deltaNeutralStrategy_deposit_shouldEmitEvent_wbtcWeth()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wbtcAddress,
            wethAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyDeposit();
        vault.deposit(0.3e8, 0.1e18, storagePointerDeltaNeutral1);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);
    }

    function test_polygon_deltaNeutralStrategy_deposit_shouldEmitEvent_wethWbtc()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            wbtcAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral2
        );

        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyDeposit();
        vault.deposit(20e18, 0.1e18, storagePointerDeltaNeutral2);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral2
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);
    }

    // =========================
    // Withdraw
    // =========================

    function test_polygon_deltaNeutralStrategy_withdraw_shouldEmitEvent_withdraw100Percents_wbtcWeth()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wbtcAddress,
            wethAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vault.deposit(0.3e8, 0.01e18, storagePointerDeltaNeutral1);

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

    function test_polygon_deltaNeutralStrategy_withdraw_shouldEmitEvent_withdraw50Percents_wbtcWeth()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wbtcAddress,
            wethAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vault.deposit(0.3e8, 0.01e18, storagePointerDeltaNeutral1);

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

    function test_polygon_deltaNeutralStrategy_withdraw_shouldEmitEvent_withdraw100Percents_wethWbtc()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            wbtcAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral2
        );

        vm.prank(address(vault));
        vault.deposit(50e18, 0.01e18, storagePointerDeltaNeutral2);

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

    function test_polygon_deltaNeutralStrategy_withdraw_shouldEmitEvent_withdraw50Percents_wethWbtc()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            wbtcAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral2
        );

        vm.prank(address(vault));
        vault.deposit(50e18, 0.01e18, storagePointerDeltaNeutral2);

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

    function test_polygon_deltaNeutralStrategy_rebalance_shouldEmitEvent_underHFRange_wbtcWeth()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wbtcAddress,
            wethAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vault.deposit(0.5e8, 0.01e18, storagePointerDeltaNeutral1);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);

        vm.warp(block.timestamp + 120);
        vm.roll(block.number + 10);

        // lowering HF under range 1.6-1.8
        vm.prank(address(vault));
        AaveActionLogic(address(vault)).withdrawAaveAction(wbtcAddress, 0.08e8);

        (, currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertLt(currentHF, 1.6e18);

        uint256 wbtcBalance = IERC20Metadata(wbtcAddress).balanceOf(
            address(vault)
        );
        vm.prank(address(vault));
        VaultLogic(payable(address(vault))).withdrawERC20(
            wbtcAddress,
            vaultOwner,
            wbtcBalance
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

    function test_polygon_deltaNeutralStrategy_rebalance_shouldEmitEvent_aboveHFRange_wbtcWeth()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wbtcAddress,
            wethAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vault.deposit(0.5e8, 0.01e18, storagePointerDeltaNeutral1);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);

        vm.warp(block.timestamp + 120);
        vm.roll(block.number + 10);

        vm.prank(vaultOwner);
        IERC20Metadata(wethAddress).transfer(address(vault), 1e18);

        // raising HF above range 1.6-1.8
        vm.prank(address(vault));
        AaveActionLogic(address(vault)).repayAaveAction(wethAddress, 1e18);

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

    function test_polygon_deltaNeutralStrategy_rebalance_shouldEmitEvent_underHFRange_wethWbtc()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            wbtcAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral2
        );

        vm.prank(address(vault));
        vault.deposit(50e18, 0.01e18, storagePointerDeltaNeutral2);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral2
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);

        vm.warp(block.timestamp + 120);
        vm.roll(block.number + 10);

        // lowering HF under range 1.6-1.8
        vm.prank(address(vault));
        AaveActionLogic(address(vault)).withdrawAaveAction(wethAddress, 10e18);

        (, currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral2
        );
        assertLt(currentHF, 1.6e18);

        uint256 wethBalance = IERC20Metadata(wethAddress).balanceOf(
            address(vault)
        );
        vm.prank(vaultOwner);
        VaultLogic(payable(address(vault))).withdrawERC20(
            wethAddress,
            vaultOwner,
            wethBalance
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

    function test_polygon_deltaNeutralStrategy_rebalance_shouldEmitEvent_aboveHFRange_wethWbtc()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            wbtcAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral2
        );

        vm.prank(address(vault));
        vault.deposit(50e18, 0.01e18, storagePointerDeltaNeutral2);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral2
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);

        vm.warp(block.timestamp + 120);
        vm.roll(block.number + 10);

        vm.prank(vaultOwner);
        IERC20Metadata(wbtcAddress).transfer(address(vault), 0.15e8);

        // raising HF above range 1.6-1.8
        vm.prank(address(vault));
        AaveActionLogic(address(vault)).repayAaveAction(wbtcAddress, 0.15e8);

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
