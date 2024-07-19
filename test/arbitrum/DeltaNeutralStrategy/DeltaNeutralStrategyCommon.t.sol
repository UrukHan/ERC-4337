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

import {DeltaNeutralStrategyBase, Registry, VaultProxyAdmin} from "./DeltaNeutralStrategyBase.t.sol";

contract TestDeltaNeutralStrategyCommon is DeltaNeutralStrategyBase {
    // mainnet USDT
    address usdtAddress = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

    // mainnet WETH
    address wethAddress = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    // mainnet DAI
    address daiAddress = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;

    IUniswapV3Pool pool;
    uint24 poolFee;

    uint256 nftId;

    DeltaNeutralStrategyLogic.InitializeWithMintParams initParams;

    function setUp() public {
        vm.createSelectFork(vm.envString("ARB_RPC_URL"));

        vm.deal(vaultOwner, 10 ether);
        vm.deal(user, 10 ether);

        donor = 0x3e0199792Ce69DC29A0a36146bFa68bd7C8D6633; // wallet for token airdrop

        vm.startPrank(donor);
        TransferHelper.safeTransfer(usdtAddress, address(vaultOwner), 1000e6);
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
        vm.deal(vaultProxy, 10 ether);

        TransferHelper.safeTransfer(usdtAddress, vaultProxy, 300e6);

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
        _mParams.fee = poolFee;
        _mParams.tickLower = ((currentTick - 4000) / 60) * 60;
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
        TransferHelper.safeApprove(usdtAddress, vaultProxy, type(uint256).max);

        // init params for initializeWithMint
        initParams.targetHealthFactor_e18 = 1.7e18;
        initParams.minTick = ((currentTick - 4000) / 60) * 60;
        initParams.maxTick = ((currentTick + 4000) / 60) * 60;
        initParams.poolFee = poolFee;
        initParams.supplyTokenAmount = 0.01e18;
        initParams.debtTokenAmount = 1e6;
        initParams.supplyToken = wethAddress;
        initParams.debtToken = usdtAddress;
        initParams.pointerToAaveChecker = storagePointerAaveChecker;
    }

    // =========================
    // Initialize
    // =========================

    function test_arb_deltaNeutralStrategy_initialize_accessControl() external {
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
            wethAddress,
            usdtAddress,
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
            wethAddress,
            usdtAddress,
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
            wethAddress,
            usdtAddress,
            storagePointerAaveChecker,
            keccak256("test pointer")
        );
    }

    function test_arb_deltaNeutralStrategy_initialize_shoulRevertIfAaveCheckerNotInitialized()
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
            wethAddress,
            usdtAddress,
            keccak256("test pointer aave checker"),
            keccak256("test pointer")
        );
    }

    function test_arb_deltaNeutralStrategy_initialize_failedValidateTokensInNFT()
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
            daiAddress,
            wethAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );
    }

    function test_arb_deltaNeutralStrategy_initialize_cannotInitializeMultipleTimes()
        external
    {
        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyInitialize();
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            usdtAddress,
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
            wethAddress,
            usdtAddress,
            storagePointerAaveChecker,
            keccak256("test pointer")
        );
    }

    function test_arb_deltaNeutralStrategy_initializeWithMint_shouldEmitEvent()
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

    function test_arb_deltaNeutralStrategy_initializeWithMint_shoulRevertIfAaveCheckerNotInitialized()
        external
    {
        initParams.pointerToAaveChecker = keccak256(
            "test pointer aave checker"
        );

        vm.prank(address(vault));
        vm.expectRevert(
            IDeltaNeutralStrategyLogic
                .DeltaNeutralStrategy_AaveCheckerNotInitialized
                .selector
        );
        vault.initializeWithMint(initParams, keccak256("test pointer"));
    }

    function test_arb_deltaNeutralStrategy_initializeWithMint_shouldSwapTicksIfMinGtMax()
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

    function test_arb_deltaNeutralStrategy_initializeWithMint_accessControl()
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

    function test_arb_deltaNeutralStrategy_initializeWithMint_cannotInitializeMultipleTimes()
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

    function test_arb_deltaNeutralStrategy_getTotalSupplyTokenBalance_shouldReturnCorrectAmount()
        external
    {
        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyInitialize();
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            usdtAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vault.deposit(4e18, 0.1e18, storagePointerDeltaNeutral1);

        uint256 totalValue = vault.getTotalSupplyTokenBalance(
            storagePointerDeltaNeutral1
        );

        assertGt(totalValue, 0);
    }

    function test_arb_deltaNeutralStrategy_getTotalSupplyTokenBalance_shouldReturnZeroIfPositionNotInitialized()
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

    function test_arb_deltaNeutralStrategy_deposit_accessControl() external {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.deposit(2e18, 0.1e18, storagePointerDeltaNeutral1);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.deposit(2e18, 0.1e18, storagePointerDeltaNeutral1);
    }

    function test_arb_deltaNeutralStrategy_deposit_failedMEVCheck() external {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            usdtAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.deposit(4e18, 0.00000001e18, storagePointerDeltaNeutral1);
    }

    function test_arb_deltaNeutralStrategy_deposit_shouldRevertIfDepositZero()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            usdtAddress,
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

    function test_arb_deltaNeutralStrategy_depositETH_accessControl() external {
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

    function test_arb_deltaNeutralStrategy_depositETH_failedMEVCheck()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            usdtAddress,
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

    function test_arb_deltaNeutralStrategy_depositETH_shouldRevertIfToken0IsNotWETH()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            usdtAddress,
            wethAddress,
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

    function test_arb_deltaNeutralStrategy_depositETH_shouldRevertIfDepositZero()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            usdtAddress,
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

    function test_arb_deltaNeutralStrategy_withdraw_accessControl() external {
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

    function test_arb_deltaNeutralStrategy_withdraw_failedMEVCheck() external {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            usdtAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.withdraw(1e18, 0.00000001e18, storagePointerDeltaNeutral1);
    }

    function test_arb_deltaNeutralStrategy_withdraw_shouldReturnAllIfSharesGtE18()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            usdtAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vault.deposit(4e18, 0.1e18, storagePointerDeltaNeutral1);

        assertGt(
            reg.lens.aaveLogicLens.getSupplyAmount(wethAddress, address(vault)),
            0
        );

        vm.prank(address(vault));
        vault.withdraw(type(uint256).max, 0.01e18, storagePointerDeltaNeutral1);

        assertEq(
            reg.lens.aaveLogicLens.getSupplyAmount(wethAddress, address(vault)),
            0
        );
    }

    // =========================
    // Rebalance
    // =========================

    function test_arb_deltaNeutralStrategy_rebalance_accessControl() external {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            usdtAddress,
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

    function test_arb_deltaNeutralStrategy_rebalance_failedMEVCheck() external {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            usdtAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vault.deposit(4e18, 0.01e18, storagePointerDeltaNeutral1);

        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.rebalance(0, storagePointerDeltaNeutral1);
    }

    // =========================
    // SetNewTargetHF
    // =========================

    function test_arb_deltaNeutralStrategy_healthFactorsAndNft_shouldReturnZeroesIfPositionNotInitialized()
        external
    {
        (uint256 targetHF, uint256 currentHF, ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertEq(targetHF, 0);
        assertEq(currentHF, 0);
    }

    function test_arb_deltaNeutralStrategy_setNewTargetHF_shouldEmitEvent()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            usdtAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        (uint256 targetHF, , ) = vault.healthFactorsAndNft(
            storagePointerDeltaNeutral1
        );
        assertEq(targetHF, 1.7e18);

        vm.prank(address(vault));
        vm.expectEmit();
        emit DeltaNeutralStrategyNewHealthFactor(1.75e18);
        vault.setNewTargetHF(1.75e18, storagePointerDeltaNeutral1);

        (targetHF, , ) = vault.healthFactorsAndNft(storagePointerDeltaNeutral1);
        assertEq(targetHF, 1.75e18);
    }

    function test_arb_deltaNeutralStrategy_setNewTargetHF_accessControl()
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

    function test_arb_deltaNeutralStrategy_setNewTargetHF_shouldRevertIfNewHFOutOfRange()
        external
    {
        vm.prank(address(vault));
        vault.initialize(
            nftId,
            1.7e18,
            wethAddress,
            usdtAddress,
            storagePointerAaveChecker,
            storagePointerDeltaNeutral1
        );

        vm.prank(address(vault));
        vm.expectRevert(
            IDeltaNeutralStrategyLogic
                .DeltaNeutralStrategy_HealthFactorOutOfRange
                .selector
        );
        vault.setNewTargetHF(1.9e18, storagePointerDeltaNeutral1);

        vm.prank(address(vault));
        vm.expectRevert(
            IDeltaNeutralStrategyLogic
                .DeltaNeutralStrategy_HealthFactorOutOfRange
                .selector
        );
        vault.setNewTargetHF(1.5e18, storagePointerDeltaNeutral1);
    }

    function test_arb_deltaNeutralStrategy_shouldRevertIfPointerNotInitialized()
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
