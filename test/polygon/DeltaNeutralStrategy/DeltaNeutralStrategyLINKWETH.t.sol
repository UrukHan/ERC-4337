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

contract TestDeltaNeutralStrategyLINKWETH is DeltaNeutralStrategyBase {
    // mainnet WETH
    address wethAddress = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    // mainnet LINK
    address linkAddress = 0x53E0bca35eC356BD5ddDFebbD1Fc0fD03FaBad39;

    IUniswapV3Pool pool =
        IUniswapV3Pool(0x3e31AB7f37c048FC6574189135D108df80F0ea26);
    uint24 poolFee;

    uint256 nftId;

    function setUp() public {
        vm.createSelectFork(vm.envString("POL_RPC_URL"));

        poolFee = pool.fee();

        vm.deal(vaultOwner, 10 ether);
        vm.deal(user, 10 ether);

        donor = 0x5cA6CA6c3709E1E6CFe74a50Cf6B2B6BA2Dadd67; // wallet for token airdrop

        vm.startPrank(donor);
        TransferHelper.safeTransfer(linkAddress, address(vaultOwner), 400e18);
        TransferHelper.safeTransfer(wethAddress, address(vaultOwner), 2e18);
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

        TransferHelper.safeTransfer(linkAddress, vaultProxy, 300e18);
        TransferHelper.safeTransfer(wethAddress, vaultProxy, 1e18);

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
        _mParams.token0 = linkAddress;
        _mParams.token1 = wethAddress;
        _mParams.fee = poolFee;
        _mParams.tickLower = ((currentTick - 4000) / 60) * 60;
        _mParams.tickUpper = ((currentTick + 4000) / 60) * 60;
        _mParams.amount0Desired = 1e18;
        _mParams.amount1Desired = 0.00001e18;
        _mParams.recipient = vaultOwner;
        _mParams.deadline = block.timestamp;

        vm.prank(vaultOwner);
        TransferHelper.safeApprove(
            linkAddress,
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
        TransferHelper.safeApprove(linkAddress, vaultProxy, type(uint256).max);
        vm.prank(vaultOwner);
        TransferHelper.safeApprove(wethAddress, vaultProxy, type(uint256).max);
    }

    // =========================
    // Deposit
    // =========================

    function test_polygon_deltaNeutralStrategy_deposit_shouldEmitEvent_linkWeth()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            linkAddress,
            wethAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyDeposit();
        vault.deposit(250e18, 0.1e18, storagePointerDeltaNeutral1);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);
    }

    function test_polygon_deltaNeutralStrategy_deposit_shouldEmitEvent_wethLink()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            linkAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral2
        );

        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyDeposit();
        vault.deposit(0.5e18, 0.1e18, storagePointerDeltaNeutral2);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral2
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);
    }

    // =========================
    // Withdraw
    // =========================

    function test_polygon_deltaNeutralStrategy_withdraw_shouldEmitEvent_withdraw100Percents_linkWeth()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            linkAddress,
            wethAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vault.deposit(250e18, 0.01e18, storagePointerDeltaNeutral1);

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

    function test_polygon_deltaNeutralStrategy_withdraw_shouldEmitEvent_withdraw50Percents_linkWeth()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            linkAddress,
            wethAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vault.deposit(250e18, 0.01e18, storagePointerDeltaNeutral1);

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

    function test_polygon_deltaNeutralStrategy_withdraw_shouldEmitEvent_withdraw100Percents_wethLink()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            linkAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral2
        );

        vm.prank(address(vault));
        vault.deposit(0.5e18, 0.01e18, storagePointerDeltaNeutral2);

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

    function test_polygon_deltaNeutralStrategy_withdraw_shouldEmitEvent_withdraw50Percents_wethLink()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            linkAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral2
        );

        vm.prank(address(vault));
        vault.deposit(0.5e18, 0.01e18, storagePointerDeltaNeutral2);

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

    function test_polygon_deltaNeutralStrategy_rebalance_shouldEmitEvent_underHFRange_linkWeth()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            linkAddress,
            wethAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vault.deposit(250e18, 0.01e18, storagePointerDeltaNeutral1);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);

        vm.warp(block.timestamp + 120);
        vm.roll(block.number + 10);

        uint256 supplyAmount = reg.lens.aaveLogicLens.getSupplyAmount(
            linkAddress,
            address(vault)
        );

        // lowering HF under range 1.6-1.8
        vm.prank(address(vault));
        AaveActionLogic(address(vault)).withdrawAaveAction(
            linkAddress,
            supplyAmount / 5
        );

        (, currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertLt(currentHF, 1.6e18);

        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyRebalance();
        vault.rebalance(1e18, storagePointerDeltaNeutral1);

        (, currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);
    }

    function test_polygon_deltaNeutralStrategy_rebalance_shouldEmitEvent_aboveHFRange_linkWeth()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            linkAddress,
            wethAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vault.deposit(250e18, 0.01e18, storagePointerDeltaNeutral1);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);

        vm.warp(block.timestamp + 120);
        vm.roll(block.number + 10);

        vm.prank(vaultOwner);
        IERC20Metadata(wethAddress).transfer(address(vault), 0.15e18);

        // raising HF above range 1.6-1.8
        vm.prank(address(vault));
        AaveActionLogic(address(vault)).repayAaveAction(wethAddress, 0.15e18);

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

    function test_polygon_deltaNeutralStrategy_rebalance_shouldEmitEvent_underHFRange_wethLink()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            linkAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral2
        );

        vm.prank(address(vault));
        vault.deposit(0.5e18, 0.01e18, storagePointerDeltaNeutral2);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral2
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);

        vm.warp(block.timestamp + 120);
        vm.roll(block.number + 10);

        // lowering HF under range 1.6-1.8
        vm.prank(address(vault));
        AaveActionLogic(address(vault)).withdrawAaveAction(wethAddress, 0.1e18);

        (, currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral2
        );
        assertLt(currentHF, 1.6e18);

        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyRebalance();
        vault.rebalance(1e18, storagePointerDeltaNeutral2);

        (, currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral2
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);
    }

    function test_polygon_deltaNeutralStrategy_rebalance_shouldEmitEvent_aboveHFRange_wethLink()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            linkAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral2
        );

        vm.prank(address(vault));
        vault.deposit(0.5e18, 0.01e18, storagePointerDeltaNeutral2);

        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral2
        );
        assertApproxEqAbs(currentHF, targetHF, 0.03e18);

        vm.warp(block.timestamp + 120);
        vm.roll(block.number + 10);

        vm.prank(vaultOwner);
        IERC20Metadata(linkAddress).transfer(address(vault), 25e18);

        // raising HF above range 1.6-1.8
        vm.prank(address(vault));
        AaveActionLogic(address(vault)).repayAaveAction(linkAddress, 25e18);

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
