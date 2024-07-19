// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IPool} from "@aave/aave-v3-core/contracts/interfaces/IPool.sol";

import {AccessControlLogic} from "../../../src/vault/logics/AccessControlLogic.sol";
import {BaseContract, Constants} from "../../../src/vault/libraries/BaseContract.sol";
import {DeltaNeutralStrategyLogic, IDeltaNeutralStrategyLogic} from "../../../src/vault/logics/OurLogic/DeltaNeutralStrategyLogic.sol";
import {AaveCheckerLogic} from "../../../src/vault/logics/Checkers/AaveCheckerLogic.sol";

import {TransferHelper} from "../../../src/vault/libraries/utils/TransferHelper.sol";
import {DexLogicLib} from "../../../src/vault/libraries/DexLogicLib.sol";

import {DeltaNeutralStrategyBase, Registry, IERC20Metadata, VaultProxyAdmin} from "./DeltaNeutralStrategyBase.t.sol";

import {IUniswapLogic} from "../../../src/vault/interfaces/ourLogic/dexAutomation/IUniswapLogic.sol";

contract TestDeltaNeutralStrategyCommon is DeltaNeutralStrategyBase {
    // mainnet USDC
    address usdcAddress = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    // mainnet WMATIC
    address wmaticAddress = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

    // mainnet WETH
    address wethAddress = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;

    IUniswapV3Pool pool =
        IUniswapV3Pool(0x88f3C15523544835fF6c738DDb30995339AD57d6);
    uint24 poolFee;

    uint256 nftId;
    uint256 nftId2;

    DeltaNeutralStrategyLogic.InitializeWithMintParams initParams;

    function setUp() public {
        vm.createSelectFork(vm.envString("POL_RPC_URL"));

        poolFee = pool.fee();

        vm.deal(vaultOwner, 10 ether);
        vm.deal(user, 10 ether);

        donor = 0xA374094527e1673A86dE625aa59517c5dE346d32; // wallet for token airdrop

        vm.startPrank(donor);
        TransferHelper.safeTransfer(usdcAddress, address(vaultOwner), 1000e6);
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
        vm.deal(vaultProxy, 10 ether);

        TransferHelper.safeTransfer(usdcAddress, vaultProxy, 300e6);

        TransferHelper.safeTransfer(wmaticAddress, vaultProxy, 100e18);

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
        (nftId, , , ) = reg.uniswapNFTPositionManager.mint(_mParams);
        vm.prank(vaultOwner);
        reg.uniswapNFTPositionManager.safeTransferFrom(
            vaultOwner,
            vaultProxy,
            nftId
        );

        vm.prank(vaultOwner);
        (nftId2, , , ) = reg.uniswapNFTPositionManager.mint(_mParams);
        vm.prank(vaultOwner);
        reg.uniswapNFTPositionManager.safeTransferFrom(
            vaultOwner,
            vaultProxy,
            nftId2
        );

        vm.prank(vaultProxy);
        IUniswapLogic(address(vault)).uniswapWithdrawPositionByShares(
            nftId2,
            1e18,
            1e18
        );

        vm.prank(vaultOwner);
        TransferHelper.safeApprove(
            wmaticAddress,
            vaultProxy,
            type(uint256).max
        );
        vm.prank(vaultOwner);
        TransferHelper.safeApprove(usdcAddress, vaultProxy, type(uint256).max);

        // init params for initializeWithMint
        initParams.targetHealthFactor_e18 = 1.7e18;
        initParams.minTick = ((currentTick - 4000) / 60) * 60;
        initParams.maxTick = ((currentTick + 4000) / 60) * 60;
        initParams.poolFee = pool.fee();
        initParams.supplyTokenAmount = 0.01e18;
        initParams.debtTokenAmount = 1e6;
        initParams.supplyToken = wmaticAddress;
        initParams.debtToken = usdcAddress;
        initParams.pointerToAaveChecker = storagePointerAaveChecker;
    }

    // =========================
    // Initialize
    // =========================

    function test_polygon_deltaNeutralStrategy_initialize_accessControl()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.initialize(
            nftId,
            1.8e18,
            wmaticAddress,
            usdcAddress,
            storagePointerAaveChecker,
            keccak256("test pointer")
        );

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.initialize(
            nftId,
            1.8e18,
            wmaticAddress,
            usdcAddress,
            storagePointerAaveChecker,
            keccak256("test pointer")
        );

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.initialize(
            nftId,
            1.8e18,
            wmaticAddress,
            usdcAddress,
            storagePointerAaveChecker,
            keccak256("test pointer")
        );
    }

    function test_polygon_deltaNeutralStrategy_initialize_shouldRevertIfAaveCheckerNotInitialized()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert(
            IDeltaNeutralStrategyLogic
                .DeltaNeutralStrategy_AaveCheckerNotInitialized
                .selector
        );
        vault.initialize(
            nftId,
            1.5e18,
            wmaticAddress,
            usdcAddress,
            keccak256("test pointer aave"),
            keccak256("test pointer")
        );
    }

    function test_polygon_deltaNeutralStrategy_initialize_failedValidateTokensInNFT()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert(
            IDeltaNeutralStrategyLogic
                .DeltaNeutralStrategy_InvalidNFTTokens
                .selector
        );
        vault.initialize(
            nftId,
            1.7e18,
            wmaticAddress,
            wethAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );
    }

    function test_polygon_deltaNeutralStrategy_initialize_cannotInitializeMultipleTimes()
        external
    {
        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyInitialize();
        vault.initialize(
            nftId,
            1.7e18,
            wmaticAddress,
            usdcAddress,
            storagePointerAaveChecker,
            keccak256("test pointer")
        );

        (, , uint256 newNftId) = vault.healthFactorsAndNft(
            keccak256("test pointer")
        );
        assertEq(newNftId, nftId);

        vm.prank(address(vault));
        vm.expectRevert(
            IDeltaNeutralStrategyLogic
                .DeltaNeutralStrategy_AlreadyInitialized
                .selector
        );
        vault.initialize(
            nftId,
            1.7e18,
            wmaticAddress,
            usdcAddress,
            storagePointerAaveChecker,
            keccak256("test pointer")
        );
    }

    function test_polygon_deltaNeutralStrategy_initializeWithMint_shouldEmitEvent()
        external
    {
        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyInitialize();
        vault.initializeWithMint(initParams, keccak256("test pointer"));

        (, , uint256 newNftId) = vault.healthFactorsAndNft(
            keccak256("test pointer")
        );

        assertNotEq(newNftId, 0);
    }

    function test_polygon_deltaNeutralStrategy_initializeWithMint_reverseTokens()
        external
    {
        // init params for initializeWithMint
        initParams.poolFee = pool.fee();
        initParams.supplyTokenAmount = 1e6;
        initParams.debtTokenAmount = 0.01e18;
        initParams.supplyToken = usdcAddress;
        initParams.debtToken = wmaticAddress;
        initParams.pointerToAaveChecker = storagePointerAaveChecker;

        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyInitialize();
        vault.initializeWithMint(initParams, keccak256("test pointer"));

        (, , uint256 newNftId) = vault.healthFactorsAndNft(
            keccak256("test pointer")
        );

        assertNotEq(newNftId, 0);

        vm.prank(address(vault));
        vault.deposit(1e6, 1e18, keccak256("test pointer"));
    }

    function test_polygon_deltaNeutralStrategy_initializeWithMint_shouldRevertIfAaveCheckerNotInitialized()
        external
    {
        initParams.pointerToAaveChecker = keccak256("test pointer aave");

        vm.prank(address(vault));
        vm.expectRevert(
            IDeltaNeutralStrategyLogic
                .DeltaNeutralStrategy_AaveCheckerNotInitialized
                .selector
        );
        vault.initializeWithMint(initParams, keccak256("test pointer"));
    }

    function test_polygon_deltaNeutralStrategy_initializeWithMint_shouldSwapTicksIfMinGtMax()
        external
    {
        int24 minTick = initParams.maxTick;
        initParams.maxTick = initParams.minTick;
        initParams.minTick = minTick;

        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyInitialize();
        vault.initializeWithMint(initParams, keccak256("test pointer"));

        (, , uint256 newNftId) = vault.healthFactorsAndNft(
            keccak256("test pointer")
        );

        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = reg
            .uniswapNFTPositionManager
            .positions(newNftId);
        assertEq(tickLower, initParams.maxTick);
        assertEq(tickUpper, initParams.minTick);
    }

    function test_polygon_deltaNeutralStrategy_initializeWithMint_accessControl()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.initializeWithMint(initParams, keccak256("test pointer"));

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.initializeWithMint(initParams, keccak256("test pointer"));

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.initializeWithMint(initParams, keccak256("test pointer"));
    }

    function test_polygon_deltaNeutralStrategy_initializeWithMint_cannotInitializeMultipleTimes()
        external
    {
        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyInitialize();
        vault.initializeWithMint(initParams, keccak256("test pointer"));

        vm.prank(address(vault));
        vm.expectRevert(
            IDeltaNeutralStrategyLogic
                .DeltaNeutralStrategy_AlreadyInitialized
                .selector
        );
        vault.initializeWithMint(initParams, keccak256("test pointer"));
    }

    // =========================
    // GetTotalSupplyTokenBalance
    // =========================

    function test_polygon_deltaNeutralStrategy_getTotalSupplyTokenBalance_shouldReturnCorrectAmount()
        external
    {
        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyInitialize();
        vault.initialize(
            nftId,
            1.7e18,
            wmaticAddress,
            usdcAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vault.deposit(100e18, 0.1e18, storagePointerDeltaNeutral1);

        uint256 totalValue = vault.getTotalSupplyTokenBalance(
            storagePointerDeltaNeutral1
        );

        assertGt(totalValue, 0);

        vm.prank(address(vault));
        vault.setNewNftId(nftId2, 1e18, storagePointerDeltaNeutral1);

        (uint256 cHF, , uint256 _nftId) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        console2.log(cHF, _nftId);
    }

    function test_polygon_deltaNeutralStrategy_getTotalSupplyTokenBalance_shouldReturnZeroIfPositionNotInitialized()
        external
    {
        uint256 totalValue = vault.getTotalSupplyTokenBalance(
            storagePointerDeltaNeutral1
        );

        assertEq(totalValue, 0);
    }

    // =========================
    // Deposit
    // =========================

    function test_polygon_deltaNeutralStrategy_deposit_accessControl()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.deposit(250e18, 0.1e18, storagePointerDeltaNeutral1);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.deposit(250e18, 0.1e18, storagePointerDeltaNeutral1);
    }

    function test_polygon_deltaNeutralStrategy_deposit_failedMEVCheck()
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
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.deposit(4e18, 0.00000001e18, storagePointerDeltaNeutral1);
    }

    function test_polygon_deltaNeutralStrategy_deposit_shouldRevertIfDepositZero()
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
        vm.expectRevert(
            IDeltaNeutralStrategyLogic.DeltaNeutralStrategy_DepositZero.selector
        );
        vault.deposit(0, 0.1e18, storagePointerDeltaNeutral1);
    }

    // =========================
    // DepositETH
    // =========================

    function test_polygon_deltaNeutralStrategy_depositETH_accessControl()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.depositETH(1 ether, 0.1 ether, storagePointerDeltaNeutral1);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.depositETH(1 ether, 0.1 ether, storagePointerDeltaNeutral1);
    }

    function test_polygon_deltaNeutralStrategy_depositETH_failedMEVCheck()
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
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.depositETH(
            1 ether,
            0.00000001 ether,
            storagePointerDeltaNeutral1
        );
    }

    function test_polygon_deltaNeutralStrategy_depositETH_shouldRevertIfToken0IsNotWETH()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            usdcAddress,
            wmaticAddress,
            storagePointerAaveChecker,
            keccak256("test pointer")
        );

        vm.prank(address(vault));
        vm.expectRevert(
            IDeltaNeutralStrategyLogic
                .DeltaNeutralStrategy_Token0IsNotWNative
                .selector
        );
        vault.depositETH(1 ether, 0.1 ether, keccak256("test pointer"));
    }

    function test_polygon_deltaNeutralStrategy_depositETH_shouldRevertIfDepositZero()
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
        vm.expectRevert(
            IDeltaNeutralStrategyLogic.DeltaNeutralStrategy_DepositZero.selector
        );
        vault.depositETH(200e18, 0.1e18, storagePointerDeltaNeutral1);
    }

    // =========================
    // Withdraw
    // =========================

    function test_polygon_deltaNeutralStrategy_withdraw_accessControl()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.withdraw(1e18, 0.1e18, storagePointerDeltaNeutral1);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.withdraw(1e18, 0.1e18, storagePointerDeltaNeutral1);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.withdraw(1e18, 0.1e18, storagePointerDeltaNeutral1);
    }

    function test_polygon_deltaNeutralStrategy_withdraw_failedMEVCheck()
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
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.withdraw(1e18, 0.00000001e18, storagePointerDeltaNeutral1);
    }

    function test_polygon_deltaNeutralStrategy_withdraw_shouldReturnAllIfSharesGtE18()
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
        vault.deposit(4e18, 0.1e18, storagePointerDeltaNeutral1);

        assertGt(
            reg.lens.aaveLogicLens.getSupplyAmount(
                wmaticAddress,
                address(vault)
            ),
            0
        );

        vm.prank(address(vault));
        vault.withdraw(type(uint256).max, 0.01e18, storagePointerDeltaNeutral1);

        assertEq(
            reg.lens.aaveLogicLens.getSupplyAmount(
                wmaticAddress,
                address(vault)
            ),
            0
        );
    }

    // =========================
    // Rebalance
    // =========================

    function test_polygon_deltaNeutralStrategy_rebalance_accessControl()
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
        vault.deposit(4e18, 0.01e18, storagePointerDeltaNeutral1);

        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.rebalance(1e18, storagePointerDeltaNeutral1);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.rebalance(1e18, storagePointerDeltaNeutral1);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.rebalance(1e18, storagePointerDeltaNeutral1);
    }

    function test_polygon_deltaNeutralStrategy_rebalance_failedMEVCheck()
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
        vault.deposit(4e18, 0.01e18, storagePointerDeltaNeutral1);

        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.rebalance(0.00000001e18, storagePointerDeltaNeutral1);
    }

    // =========================
    // SetNewTargetHF
    // =========================

    function test_polygon_deltaNeutralStrategy_healthFactorsAndNft_shouldReturnZeroesIfPositionNotInitialized()
        external
    {
        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertEq(targetHF, 0);
        assertEq(currentHF, 0);
    }

    function test_polygon_deltaNeutralStrategy_setNewTargetHF_shouldEmitEvent()
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

        (uint256 targetHF, , ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertEq(targetHF, 1.7e18);

        vm.prank(vaultOwner);
        vm.expectEmit();
        emit DeltaNeutralStrategyNewHealthFactor(1.75e18);
        vault.setNewTargetHF(1.75e18, storagePointerDeltaNeutral1);

        (targetHF, , ) = vault.healthFactorsAndNft(storagePointerDeltaNeutral1);
        assertEq(targetHF, 1.75e18);
    }

    function test_polygon_deltaNeutralStrategy_setNewTargetHF_accessControl()
        external
    {
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.setNewTargetHF(1.65e18, storagePointerDeltaNeutral1);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.setNewTargetHF(1.65e18, storagePointerDeltaNeutral1);
    }

    function test_polygon_deltaNeutralStrategy_setNewTargetHF_shouldRevertIfNewHFOutOfRange()
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

        vm.prank(vaultOwner);
        vm.expectRevert(
            IDeltaNeutralStrategyLogic
                .DeltaNeutralStrategy_HealthFactorOutOfRange
                .selector
        );
        vault.setNewTargetHF(1.9e18, storagePointerDeltaNeutral1);

        vm.prank(vaultOwner);
        vm.expectRevert(
            IDeltaNeutralStrategyLogic
                .DeltaNeutralStrategy_HealthFactorOutOfRange
                .selector
        );
        vault.setNewTargetHF(1.5e18, storagePointerDeltaNeutral1);
    }

    function test_polygon_deltaNeutralStrategy_shouldRevertIfPointerNotInitialized()
        external
    {
        bytes32 _pointer = keccak256("not initialized pointer");
        vm.prank(vaultOwner);
        vm.expectRevert(
            IDeltaNeutralStrategyLogic
                .DeltaNeutralStrategy_NotInitialized
                .selector
        );
        vault.setNewTargetHF(1e18, _pointer);

        vm.prank(address(vault));
        vm.expectRevert(
            IDeltaNeutralStrategyLogic
                .DeltaNeutralStrategy_NotInitialized
                .selector
        );
        vault.deposit(0, 1e18, _pointer);

        vm.prank(address(vault));
        vm.expectRevert(
            IDeltaNeutralStrategyLogic
                .DeltaNeutralStrategy_NotInitialized
                .selector
        );
        vault.withdraw(1e18, 1e18, _pointer);

        vm.prank(address(vault));
        vm.expectRevert(
            IDeltaNeutralStrategyLogic
                .DeltaNeutralStrategy_NotInitialized
                .selector
        );
        vault.rebalance(1e18, _pointer);
    }
}
