// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IAutomate, LibDataTypes} from "@gelato/contracts/interfaces/IAutomate.sol";

import {ProtocolFees} from "../../src/ProtocolFees.sol";

import {IV3SwapRouter} from "../../src/vault/interfaces/external/IV3SwapRouter.sol";
import {AccessControlLogic} from "../../src/vault/logics/AccessControlLogic.sol";
import {BaseContract, Constants} from "../../src/vault/libraries/BaseContract.sol";
import {EntryPointLogic, IEntryPointLogic} from "../../src/vault/logics/EntryPointLogic.sol";
import {ExecutionLogic} from "../../src/vault/logics/ExecutionLogic.sol";
import {VaultLogic} from "../../src/vault/logics/VaultLogic.sol";
import {VaultFactory} from "../../src/VaultFactory.sol";
import {PancakeswapLogic} from "../../src/vault/logics/OurLogic/dexAutomation/PancakeswapLogic.sol";
import {DeltaNeutralStrategyLogic} from "../../src/vault/logics/OurLogic/DeltaNeutralStrategyLogic.sol";
import {AaveCheckerLogic} from "../../src/vault/logics/Checkers/AaveCheckerLogic.sol";
import {TimeCheckerLogic} from "../../src/vault/logics/Checkers/TimeCheckerLogic.sol";
import {PriceCheckerLogicPancakeswap} from "../../src/vault/logics/Checkers/PriceCheckerLogicPancakeswap.sol";
import {TransferHelper} from "../../src/vault/libraries/utils/TransferHelper.sol";
import {DexLogicLib} from "../../src/vault/libraries/DexLogicLib.sol";

import {FullDeploy, Registry, VaultProxyAdmin} from "../../script/FullDeploy.s.sol";

contract TestEntryPointLogic is Test, FullDeploy {
    bool isTest = true;

    address gelato;

    Registry.Contracts reg;
    address cakeAddress = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82; // mainnet CAKE
    address wbnbAddress = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; // mainnet WBNB
    address donor = 0x8894E0a0c962CB723c1976a4421c95949bE2D4E3; // wallet for token airdropwallet for token airdrop
    IUniswapV3Pool pool =
        IUniswapV3Pool(0x133B3D95bAD5405d14d53473671200e9342896BF);
    uint24 poolFee;

    address vault;

    address vaultOwner = makeAddr("VAULT_OWNER");
    address executor = makeAddr("EXECUTOR");
    address user = makeAddr("USER");

    uint256 nftId;

    bytes[] multicallData;

    function setUp() external {
        vm.createSelectFork(vm.envString("BNB_RPC_URL"));
        vm.txGasPrice(3000000000);

        poolFee = pool.fee();

        vm.startPrank(donor);
        IERC20(cakeAddress).transfer(vaultOwner, 5000e18);
        IERC20(wbnbAddress).transfer(vaultOwner, 10e18);
        vm.stopPrank();

        reg = deploySystemContracts(
            isTest,
            Registry.contractsByChainId(block.chainid)
        );

        gelato = reg.automateGelato.gelato();

        reg.protocolFees = new ProtocolFees(vaultOwner);
        reg.logics.entryPointLogic = address(
            new EntryPointLogic(reg.automateGelato, reg.protocolFees)
        );
        reg.logics.executionLogic = address(
            new ExecutionLogic(reg.protocolFees)
        );

        uint256 nonce = vm.getNonce(address(this));
        reg.vaultProxyAdmin = new VaultProxyAdmin(
            vm.computeCreateAddress(address(this), nonce + 3)
        );

        (VaultFactory vaultFactory, ) = addImplementation(
            reg,
            isTest,
            address(this)
        );

        vm.startPrank(vaultOwner);
        vault = vaultFactory.deploy(1, 1);

        (, bytes memory data) = address(pool).staticcall(
            // 0x3850c7bd - selector of "slot0()"
            abi.encodeWithSelector(0x3850c7bd)
        );
        (, int24 currentTick, , , , , ) = abi.decode(
            data,
            (uint160, int24, uint16, uint16, uint16, uint256, bool)
        );
        int24 minTick = ((currentTick - 4000) / 50) * 50;
        int24 maxTick = ((currentTick + 4000) / 50) * 50;

        uint256 RTarget = reg.lens.dexLogicLens.getTargetRE18ForTickRange(
            minTick,
            maxTick,
            pool
        );
        uint160 sqrtPriceX96 = reg.lens.dexLogicLens.getCurrentSqrtRatioX96(
            pool
        );

        uint256 wbnbAmount = reg.lens.dexLogicLens.token1AmountForTargetRE18(
            sqrtPriceX96,
            500e6,
            1e18,
            RTarget,
            poolFee
        );

        uint256 cakeAmount = reg.lens.dexLogicLens.token0AmountForTargetRE18(
            sqrtPriceX96,
            wbnbAmount,
            RTarget
        );

        IERC20(wbnbAddress).approve(
            address(reg.pancakeswapNFTPositionManager),
            wbnbAmount
        );
        IERC20(cakeAddress).approve(
            address(reg.pancakeswapNFTPositionManager),
            cakeAmount
        );

        INonfungiblePositionManager.MintParams memory _mParams;
        _mParams.token0 = cakeAddress;
        _mParams.token1 = wbnbAddress;
        _mParams.fee = poolFee;
        _mParams.tickLower = minTick;
        _mParams.tickUpper = maxTick;
        _mParams.amount0Desired = cakeAmount;
        _mParams.amount1Desired = wbnbAmount;
        _mParams.recipient = vaultOwner;
        _mParams.deadline = block.timestamp;

        // mint new nft for tests
        (nftId, , , ) = reg.pancakeswapNFTPositionManager.mint(_mParams);

        reg.pancakeswapNFTPositionManager.safeTransferFrom(
            vaultOwner,
            vault,
            nftId
        );

        deal(vault, 1 ether);

        IERC20(wbnbAddress).approve(vault, type(uint256).max);
        IERC20(cakeAddress).approve(vault, type(uint256).max);

        AccessControlLogic(vault).grantRole(
            Constants.EXECUTOR_ROLE,
            address(executor)
        );

        IERC20(cakeAddress).transfer(
            vault,
            IERC20(cakeAddress).balanceOf(vaultOwner)
        );
        IERC20(wbnbAddress).transfer(
            vault,
            IERC20(wbnbAddress).balanceOf(vaultOwner)
        );

        vm.stopPrank();
    }

    // =========================
    // AddWorkflow
    // =========================

    function test_bnb_entryPointLogic_addWorkflow_shouldUpdateState() external {
        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeAndPriceCheckers();

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflow,
                (checkers, actions, executor, 0)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        IEntryPointLogic.Workflow memory workflow = IEntryPointLogic(vault)
            .getWorkflow(0);
        assertEq(workflow.checkers[0].storageRef, checkers[0].storageRef);
        assertEq(workflow.checkers[0].data, checkers[0].data);
        assertEq(workflow.checkers[1].storageRef, checkers[1].storageRef);
        assertEq(workflow.checkers[1].data, checkers[1].data);
        assertEq(workflow.actions[0].storageRef, actions[0].storageRef);
        assertEq(workflow.actions[0].data, actions[0].data);
        assertEq(workflow.executor, executor);
        assertEq(workflow.counter, 0); // infinite executions
    }

    event TimeCheckerInitialized();
    event PriceCheckerInitialized();

    function test_bnb_entryPointLogic_addWorkflow_shouldExecuteInitCalls()
        external
    {
        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeAndPriceCheckers();

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflow,
                (checkers, actions, executor, 0)
            )
        );

        vm.prank(vaultOwner);
        vm.expectEmit();
        emit TimeCheckerInitialized();
        vm.expectEmit();
        emit PriceCheckerInitialized();
        ExecutionLogic(vault).multicall(multicallData);
    }

    function test_bnb_entryPointLogic_addWorkflow_shouldGrantRole() external {
        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeAndPriceCheckers();

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflow,
                (checkers, actions, executor, 0)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        assertTrue(
            AccessControlLogic(address(vault)).hasRole(
                Constants.EXECUTOR_ROLE,
                executor
            )
        );
    }

    function test_bnb_entryPointLogic_addWorkflow_accessControl() external {
        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeAndPriceCheckers();

        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        IEntryPointLogic(vault).addWorkflow(checkers, actions, vaultOwner, 0);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        IEntryPointLogic(vault).addWorkflow(checkers, actions, executor, 0);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        IEntryPointLogic(vault).addWorkflow(checkers, actions, user, 0);
    }

    // =========================
    // Run
    // =========================

    event PancakeswapAutoCompound(uint256 nftId);

    function test_bnb_entryPointLogic_run_successfulRunPancakeswap() external {
        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeAndPriceCheckers();

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflow,
                (checkers, actions, executor, 0)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        _rateUp();
        vm.warp(block.timestamp + 3601);
        vm.roll(block.number + 300);

        vm.prank(executor);
        vm.expectEmit();
        emit PancakeswapAutoCompound(nftId);
        IEntryPointLogic(vault).run(0);
    }

    function test_bnb_entryPointLogic_run_unsuccessfulRun() external {
        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeAndPriceCheckers();

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflow,
                (checkers, actions, executor, 0)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        vm.prank(executor);
        vm.expectRevert(
            IEntryPointLogic.EntryPoint_TriggerVerificationFailed.selector
        );
        IEntryPointLogic(vault).run(0);
    }

    function test_bnb_entryPointLogic_run_shouldRevertWithRevertedAction()
        external
    {
        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeAndPriceCheckers();

        actions[0].data = abi.encodeCall(
            PancakeswapLogic.pancakeswapAutoCompound,
            (nftId, 0)
        );

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflow,
                (checkers, actions, executor, 0)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        _rateUp();
        vm.warp(block.timestamp + 3601);
        vm.roll(block.number + 300);

        vm.prank(executor);
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        IEntryPointLogic(vault).run(0);
    }

    event EntryPointRun(address indexed executor, uint256 wokrflowKey);

    function test_bnb_entryPointLogic_run_shouldSendDittoFeeToDittoTreasury()
        external
    {
        address treasury = makeAddr("treasury");
        vm.prank(vaultOwner);
        reg.protocolFees.setTreasury(treasury);
        vm.prank(vaultOwner);
        reg.protocolFees.setAutomationFee(1e18, 0);

        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeChecker();

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflow,
                (checkers, actions, executor, 0)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        vm.warp(block.timestamp + 3601);
        vm.roll(block.number + 300);

        uint256 balanceBefore = treasury.balance;

        vm.prank(executor);
        vm.expectEmit(address(vault));
        emit EntryPointRun(executor, 0);
        IEntryPointLogic(vault).run(0);

        // Check if balance has increased
        assertGt(treasury.balance - balanceBefore, 0);
    }

    function test_bnb_entryPointLogic_run_shouldRevertIfFeeDoesNotEnough()
        external
    {
        address treasury = makeAddr("treasury");
        vm.prank(vaultOwner);
        reg.protocolFees.setTreasury(treasury);
        vm.prank(vaultOwner);
        reg.protocolFees.setAutomationFee(1e18, 0);

        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeChecker();

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflow,
                (checkers, actions, executor, 0)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        vm.warp(block.timestamp + 3601);
        vm.roll(block.number + 300);

        vm.prank(vaultOwner);
        VaultLogic(payable(address(vault))).withdrawTotalNative(vaultOwner);
        vm.prank(executor);
        vm.expectRevert(
            TransferHelper.TransferHelper_SafeTransferNativeError.selector
        );
        IEntryPointLogic(vault).run(0);
    }

    function test_bnb_entryPointLogic_run_shouldRevertIfWorkflowDoesNotExists()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            IEntryPointLogic.EntryPoint_WorkflowDoesNotExist.selector
        );
        IEntryPointLogic(vault).run(0);
    }

    event EntryPointWorkflowStatusDeactivated(uint256 workflowKey);

    function test_bnb_entryPointLogic_run_singleExecute() external {
        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeChecker();

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflow,
                (checkers, actions, executor, 1)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        vm.warp(block.timestamp + 3601);
        vm.roll(block.number + 300);

        vm.prank(executor);
        vm.expectEmit();
        emit EntryPointWorkflowStatusDeactivated(0);
        IEntryPointLogic(vault).run(0);
    }

    function test_bnb_entryPointLogic_run_executeFiveTimes() external {
        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeChecker();

        checkers = new IEntryPointLogic.Checker[](0);

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflow,
                (checkers, actions, executor, 5)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        vm.startPrank(executor);
        IEntryPointLogic(vault).run(0);
        IEntryPointLogic(vault).run(0);
        IEntryPointLogic(vault).run(0);
        IEntryPointLogic(vault).run(0);

        vm.expectEmit();
        emit EntryPointWorkflowStatusDeactivated(0);
        IEntryPointLogic(vault).run(0);

        vm.expectRevert(
            IEntryPointLogic.EntryPoint_WorkflowIsInactive.selector
        );
        IEntryPointLogic(vault).run(0);
        vm.stopPrank();
    }

    // =========================
    // CreateTask
    // =========================

    function test_bnb_entryPointLogic_createTask_shouldCreateTaskForWorkflow()
        external
    {
        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeChecker();

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflow,
                (checkers, actions, executor, 0)
            )
        );

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.createTask,
                (IEntryPointLogic(vault).getNextWorkflowKey())
            )
        );

        bytes32 taskIdBefore = IEntryPointLogic(vault).getTaskId(0);
        assertEq(taskIdBefore, bytes32(0));

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        bytes32 taskIdAfter = IEntryPointLogic(vault).getTaskId(0);

        assertNotEq(taskIdBefore, taskIdAfter);
    }

    function test_bnb_entryPointLogic_createTask_cannotCreateSeveralTaskForOneWorkflow()
        external
    {
        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeChecker();

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflowAndGelatoTask,
                (checkers, actions, executor, 0)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        multicallData[0] = abi.encodeCall(IEntryPointLogic.createTask, (0));

        vm.prank(vaultOwner);
        vm.expectRevert(IEntryPointLogic.Gelato_TaskAlreadyStarted.selector);
        ExecutionLogic(vault).multicall(multicallData);
    }

    function test_bnb_entryPointLogic_createTask_shouldRevertIfWorkflowDoesNotExists()
        external
    {
        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.createTask,
                (IEntryPointLogic(vault).getNextWorkflowKey())
            )
        );

        vm.prank(vaultOwner);
        vm.expectRevert(
            IEntryPointLogic.EntryPoint_WorkflowDoesNotExist.selector
        );
        ExecutionLogic(vault).multicall(multicallData);
    }

    function test_bnb_entryPointLogic_createTask_accessControl() external {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        IEntryPointLogic(vault).createTask(0);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        IEntryPointLogic(vault).createTask(0);
    }

    // =========================
    // CancelTask
    // =========================

    event GelatoTaskCancelled(uint256 workflowKey, bytes32 id);

    function test_bnb_entryPointLogic_cancelTask_shouldCancelTaskForWorkflow()
        external
    {
        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeChecker();

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflowAndGelatoTask,
                (checkers, actions, executor, 0)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        bytes32 taskId = IEntryPointLogic(vault).getTaskId(0);
        assertNotEq(taskId, bytes32(0));

        vm.prank(vaultOwner);
        vm.expectEmit();
        emit GelatoTaskCancelled(0, taskId);
        IEntryPointLogic(vault).cancelTask(0);

        taskId = IEntryPointLogic(vault).getTaskId(0);
        assertEq(taskId, bytes32(0));
    }

    function test_bnb_entryPointLogic_cancelTask_cannotCancelTaskWhichNotExists()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            IEntryPointLogic.Gelato_CannotCancelTaskWhichNotExists.selector
        );
        IEntryPointLogic(vault).cancelTask(0);
    }

    function test_bnb_entryPointLogic_cancelTask_accessControl() external {
        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeChecker();

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflowAndGelatoTask,
                (checkers, actions, executor, 0)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        IEntryPointLogic(vault).cancelTask(0);
    }

    function test_bnb_entryPointLogic_runGelato_successfulRunGelato() external {
        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeAndPriceCheckers();

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflowAndGelatoTask,
                (checkers, actions, executor, 0)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        (bool canExec, bytes memory data) = IEntryPointLogic(vault)
            .canExecWorkflowCheck(0);
        assertFalse(canExec);
        assertEq(
            data,
            abi.encodePacked(
                "Workflow cannot be executed: ",
                Strings.toString(uint256(0))
            )
        );

        _rateUp();
        vm.warp(block.timestamp + 3601);
        vm.roll(block.number + 300);

        (canExec, data) = IEntryPointLogic(vault).canExecWorkflowCheck(0);
        assertTrue(canExec);
        assertEq(data, abi.encodeCall(IEntryPointLogic.runGelato, (0)));

        vm.expectEmit();
        emit PancakeswapAutoCompound(nftId);
        _executeGelato(0, data);
    }

    function test_bnb_entryPointLogic_runGelato_shouldSendDittoFee() external {
        address treasury = makeAddr("treasury");

        assertEq(treasury.balance, 0);

        vm.prank(vaultOwner);
        reg.protocolFees.setTreasury(treasury);
        vm.prank(vaultOwner);
        reg.protocolFees.setAutomationFee(1e18, 0.5e18);

        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeAndPriceCheckers();

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflowAndGelatoTask,
                (checkers, actions, executor, 0)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        _rateUp();
        vm.warp(block.timestamp + 3601);
        vm.roll(block.number + 300);

        _executeGelato(0, abi.encodeCall(IEntryPointLogic.runGelato, (0)));

        assertGt(treasury.balance, 0);
    }

    function test_bnb_entryPointLogic_runGelato_successfulRunGelatoAndCancelTaskIfCounterIsZero()
        external
    {
        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeAndPriceCheckers();

        checkers = new IEntryPointLogic.Checker[](0);

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflowAndGelatoTask,
                (checkers, actions, executor, 5)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        (bool canExec, bytes memory data) = IEntryPointLogic(vault)
            .canExecWorkflowCheck(0);
        assertTrue(canExec);
        assertEq(data, abi.encodeCall(IEntryPointLogic.runGelato, (0)));

        _executeGelato(0, data);
        _executeGelato(0, data);
        _executeGelato(0, data);
        _executeGelato(0, data);

        vm.expectEmit();
        emit GelatoTaskCancelled(0, IEntryPointLogic(vault).getTaskId(0));
        _executeGelato(0, data);

        vm.prank(executor);
        vm.expectRevert(
            IEntryPointLogic.EntryPoint_WorkflowIsInactive.selector
        );
        IEntryPointLogic(vault).run(0);
    }

    function test_bnb_entryPointLogic_runGelato_onlyDedicatedMsgSenderRevert()
        external
    {
        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeAndPriceCheckers();

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflowAndGelatoTask,
                (checkers, actions, executor, 0)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        vm.prank(executor);
        vm.expectRevert(
            IEntryPointLogic.Gelato_MsgSenderIsNotDedicated.selector
        );
        IEntryPointLogic(vault).runGelato(0);
    }

    function test_bnb_entryPointLogic_runGelato_shouldRevertIfGelatoFeeNotEnough()
        external
    {
        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeAndPriceCheckers();

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflowAndGelatoTask,
                (checkers, actions, executor, 0)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        vm.prank(vaultOwner);
        VaultLogic(payable(address(vault))).withdrawTotalNative(vaultOwner);

        _rateUp();
        vm.warp(block.timestamp + 3601);
        vm.roll(block.number + 300);

        (bool canExec, bytes memory data) = IEntryPointLogic(vault)
            .canExecWorkflowCheck(0);
        assertTrue(canExec);
        assertEq(data, abi.encodeCall(IEntryPointLogic.runGelato, (0)));

        vm.expectRevert("Automate.exec: OpsProxy.executeCall: NoErrorSelector");
        _executeGelato(0, data);
    }

    function test_bnb_entryPointLogic_runGelato_shouldRevertIfWorkflowDoesNotExists()
        external
    {
        vm.prank(IEntryPointLogic(vault).dedicatedMessageSender());
        vm.expectRevert(
            IEntryPointLogic.EntryPoint_WorkflowDoesNotExist.selector
        );
        IEntryPointLogic(vault).runGelato(0);
    }

    // =========================
    // Active status logic
    // =========================

    function test_bnb_entryPointLogic_deactivateVault_shouldStopAllWorkflows()
        external
    {
        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeChecker();

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflow,
                (checkers, actions, executor, 0)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        assertTrue(IEntryPointLogic(vault).isActive());

        vm.prank(vaultOwner);
        bytes[] memory callbacks;
        IEntryPointLogic(vault).deactivateVault(callbacks);

        assertFalse(IEntryPointLogic(vault).isActive());

        vm.prank(executor);
        vm.expectRevert(IEntryPointLogic.EntryPoint_VaultIsInactive.selector);
        IEntryPointLogic(vault).run(0);
    }

    function test_bnb_entryPointLogic_deactivateVault_shouldRevertIfVaultAlreadyDeactivated()
        external
    {
        vm.startPrank(vaultOwner);

        bytes[] memory callbacks;
        IEntryPointLogic(vault).deactivateVault(callbacks);

        assertFalse(IEntryPointLogic(vault).isActive());

        vm.expectRevert(IEntryPointLogic.EntryPoint_AlreadyInactive.selector);
        IEntryPointLogic(vault).deactivateVault(callbacks);

        vm.stopPrank();
    }

    function test_bnb_entryPointLogic_deactivateVault_shouldExecuteCallbacks()
        external
    {
        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeChecker();

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflow,
                (checkers, actions, executor, 0)
            )
        );

        vm.startPrank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        bytes[] memory callbacks = new bytes[](1);
        callbacks[0] = abi.encodeCall(IEntryPointLogic.deactivateWorkflow, (0));
        IEntryPointLogic(vault).deactivateVault(callbacks);

        assertFalse(IEntryPointLogic(vault).isActive());

        IEntryPointLogic.Workflow memory workflow = IEntryPointLogic(vault)
            .getWorkflow(0);
        assertTrue(workflow.inactive);
    }

    function test_bnb_entryPointLogic_deactivateVault_accessControl() external {
        bytes[] memory callbacks;

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        IEntryPointLogic(vault).deactivateVault(callbacks);
    }

    function test_bnb_entryPointLogic_activateVault_shouldRunAllWorkflows()
        external
    {
        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeChecker();

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflow,
                (checkers, actions, executor, 0)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        vm.prank(vaultOwner);
        bytes[] memory callbacks;
        IEntryPointLogic(vault).deactivateVault(callbacks);

        assertFalse(IEntryPointLogic(vault).isActive());

        vm.prank(executor);
        vm.expectRevert(IEntryPointLogic.EntryPoint_VaultIsInactive.selector);
        IEntryPointLogic(vault).run(0);

        vm.prank(vaultOwner);
        IEntryPointLogic(vault).activateVault(callbacks);

        assertTrue(IEntryPointLogic(vault).isActive());

        vm.warp(block.timestamp + 3601);
        vm.roll(block.number + 300);

        vm.prank(executor);
        vm.expectEmit();
        emit PancakeswapAutoCompound(nftId);
        IEntryPointLogic(vault).run(0);
    }

    function test_bnb_entryPointLogic_activateVault_shouldRevertIfVaultAlreadyActivated()
        external
    {
        bytes[] memory callbacks;

        assertTrue(IEntryPointLogic(vault).isActive());

        vm.prank(vaultOwner);
        vm.expectRevert(IEntryPointLogic.EntryPoint_AlreadyActive.selector);
        IEntryPointLogic(vault).activateVault(callbacks);
    }

    function test_bnb_entryPointLogic_activateVault_shouldExecuteCallbacks()
        external
    {
        bytes[] memory callbacks;
        vm.prank(vaultOwner);
        IEntryPointLogic(vault).deactivateVault(callbacks);
        assertFalse(IEntryPointLogic(vault).isActive());

        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeChecker();

        vm.startPrank(vaultOwner);
        callbacks = new bytes[](1);
        callbacks[0] = abi.encodeCall(
            IEntryPointLogic.addWorkflow,
            (checkers, actions, executor, 0)
        );
        IEntryPointLogic(vault).activateVault(callbacks);
        assertTrue(IEntryPointLogic(vault).isActive());

        IEntryPointLogic.Workflow memory workflow = IEntryPointLogic(vault)
            .getWorkflow(0);
        assertEq(workflow.checkers.length, 1);
        assertEq(workflow.actions.length, 1);
        assertEq(workflow.executor, executor);
    }

    function test_bnb_entryPointLogic_activateVault_accessControl() external {
        bytes[] memory callbacks;

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        IEntryPointLogic(vault).activateVault(callbacks);
    }

    function test_bnb_entryPointLogic_deactivateWorkflow_shouldStopWorkflow()
        external
    {
        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeChecker();

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflow,
                (checkers, actions, executor, 0)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        IEntryPointLogic.Workflow memory workflow = IEntryPointLogic(vault)
            .getWorkflow(0);
        assertFalse(workflow.inactive);

        vm.prank(vaultOwner);
        IEntryPointLogic(vault).deactivateWorkflow(0);
        workflow = IEntryPointLogic(vault).getWorkflow(0);
        assertTrue(workflow.inactive);

        vm.prank(executor);
        vm.expectRevert(
            IEntryPointLogic.EntryPoint_WorkflowIsInactive.selector
        );
        IEntryPointLogic(vault).run(0);
    }

    function test_bnb_entryPointLogic_deactivateWorkflow_shouldRevertIfWorkflowAlreadyDeactivated()
        external
    {
        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeChecker();

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflow,
                (checkers, actions, executor, 0)
            )
        );

        vm.startPrank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        IEntryPointLogic(vault).deactivateWorkflow(0);
        IEntryPointLogic.Workflow memory workflow = IEntryPointLogic(vault)
            .getWorkflow(0);
        assertTrue(workflow.inactive);

        vm.expectRevert(IEntryPointLogic.EntryPoint_AlreadyInactive.selector);
        IEntryPointLogic(vault).deactivateWorkflow(0);

        vm.stopPrank();
    }

    function test_bnb_entryPointLogic_deactivateWorkflow_accessControl()
        external
    {
        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeChecker();

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflow,
                (checkers, actions, executor, 0)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        IEntryPointLogic(vault).deactivateWorkflow(0);
    }

    function test_bnb_entryPointLogic_deactivateWorkflow_shouldRevertIfWorkflowDoesNotExists()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            IEntryPointLogic.EntryPoint_WorkflowDoesNotExist.selector
        );
        IEntryPointLogic(vault).deactivateWorkflow(0);
    }

    function test_bnb_entryPointLogic_activateWorkflow_shouldRunWorkflow()
        external
    {
        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeChecker();

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflow,
                (checkers, actions, executor, 0)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        vm.prank(vaultOwner);
        IEntryPointLogic(vault).deactivateWorkflow(0);

        IEntryPointLogic.Workflow memory workflow = IEntryPointLogic(vault)
            .getWorkflow(0);
        assertTrue(workflow.inactive);

        vm.prank(executor);
        vm.expectRevert(
            IEntryPointLogic.EntryPoint_WorkflowIsInactive.selector
        );
        IEntryPointLogic(vault).run(0);

        vm.prank(vaultOwner);
        IEntryPointLogic(vault).activateWorkflow(0);

        workflow = IEntryPointLogic(vault).getWorkflow(0);
        assertFalse(workflow.inactive);

        vm.warp(block.timestamp + 3601);
        vm.roll(block.number + 300);

        vm.prank(executor);
        vm.expectEmit();
        emit PancakeswapAutoCompound(nftId);
        IEntryPointLogic(vault).run(0);
    }

    function test_bnb_entryPointLogic_activateWorkflow_shouldRevertIfWorkflowAlreadyActivated()
        external
    {
        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeChecker();

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflow,
                (checkers, actions, executor, 0)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        IEntryPointLogic.Workflow memory workflow = IEntryPointLogic(vault)
            .getWorkflow(0);
        assertFalse(workflow.inactive);

        vm.prank(vaultOwner);
        vm.expectRevert(IEntryPointLogic.EntryPoint_AlreadyActive.selector);
        IEntryPointLogic(vault).activateWorkflow(0);
    }

    function test_bnb_entryPointLogic_activateWorkflow_accessControl()
        external
    {
        (
            IEntryPointLogic.Checker[] memory checkers,
            IEntryPointLogic.Action[] memory actions
        ) = _checkersAndActionsWithTimeChecker();

        multicallData.push(
            abi.encodeCall(
                IEntryPointLogic.addWorkflow,
                (checkers, actions, executor, 0)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        IEntryPointLogic(vault).activateWorkflow(0);
    }

    function test_bnb_entryPointLogic_activateWorkflow_shouldRevertIfWorkflowDoesNotExists()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            IEntryPointLogic.EntryPoint_WorkflowDoesNotExist.selector
        );
        IEntryPointLogic(vault).activateWorkflow(0);
    }

    // =========================
    // Helpers
    // =========================

    function _checkersAndActionsWithTimeAndPriceCheckers()
        internal
        view
        returns (
            IEntryPointLogic.Checker[] memory,
            IEntryPointLogic.Action[] memory
        )
    {
        IEntryPointLogic.Checker[]
            memory checkers = new IEntryPointLogic.Checker[](2);
        IEntryPointLogic.Action[]
            memory actions = new IEntryPointLogic.Action[](1);

        checkers[0].data = abi.encodeWithSelector(
            TimeCheckerLogic.checkTime.selector
        );
        checkers[0].viewData = abi.encodeWithSelector(
            TimeCheckerLogic.checkTimeView.selector
        );
        checkers[0].storageRef = "time.checker.pointer";
        checkers[0].initData = abi.encodeWithSelector(
            TimeCheckerLogic.timeCheckerInitialize.selector,
            block.timestamp,
            3600
        );

        uint256 targetRate = reg.dittoOracle.consult(
            cakeAddress,
            1e18,
            wbnbAddress,
            poolFee,
            address(reg.pancakeswapFactory)
        );

        checkers[1].data = abi.encodeWithSelector(
            PriceCheckerLogicPancakeswap.pancakeswapCheckGTTargetRate.selector
        );
        checkers[1].viewData = abi.encodeWithSelector(
            PriceCheckerLogicPancakeswap.pancakeswapCheckGTTargetRate.selector
        );
        checkers[1].storageRef = "price.checker.pointer";
        checkers[1].initData = abi.encodeWithSelector(
            PriceCheckerLogicPancakeswap
                .priceCheckerPancakeswapInitialize
                .selector,
            pool,
            targetRate
        );

        actions[0].data = abi.encodeCall(
            PancakeswapLogic.pancakeswapAutoCompound,
            (nftId, 0.01e18)
        );

        return (checkers, actions);
    }

    function _checkersAndActionsWithTimeChecker()
        internal
        view
        returns (
            IEntryPointLogic.Checker[] memory,
            IEntryPointLogic.Action[] memory
        )
    {
        IEntryPointLogic.Checker[]
            memory checkers = new IEntryPointLogic.Checker[](1);
        IEntryPointLogic.Action[]
            memory actions = new IEntryPointLogic.Action[](1);

        checkers[0].data = abi.encodeWithSelector(
            TimeCheckerLogic.checkTime.selector
        );
        checkers[0].viewData = abi.encodeWithSelector(
            TimeCheckerLogic.checkTimeView.selector
        );
        checkers[0].storageRef = "time.checker.pointer2";
        checkers[0].initData = abi.encodeWithSelector(
            TimeCheckerLogic.timeCheckerInitialize.selector,
            block.timestamp,
            3600
        );

        actions[0].data = abi.encodeCall(
            PancakeswapLogic.pancakeswapAutoCompound,
            (nftId, 0.01e18)
        );

        return (checkers, actions);
    }

    function _executeGelato(uint256 workflowKey, bytes memory data) private {
        LibDataTypes.ModuleData memory moduleData = LibDataTypes.ModuleData({
            modules: new LibDataTypes.Module[](2),
            args: new bytes[](2)
        });

        moduleData.modules[0] = LibDataTypes.Module.RESOLVER;
        moduleData.modules[1] = LibDataTypes.Module.PROXY;

        moduleData.args[0] = abi.encode(
            vault,
            abi.encodeCall(IEntryPointLogic.canExecWorkflowCheck, (workflowKey))
        );
        moduleData.args[1] = bytes("");

        vm.prank(gelato);
        IAutomate(address(reg.automateGelato)).exec(
            address(vault), // _taskCreator,
            address(vault), // _execAddress,
            data, // _execData,
            moduleData, // _moduleData,
            0.1 ether, // _txFee,
            Constants.ETH, // _feeToken,
            true // _revertOnFailure
        );
    }

    // Rate up
    function _rateUp() internal {
        vm.startPrank(donor);
        TransferHelper.safeApprove(
            wbnbAddress,
            address(reg.pancakeswapRouter),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            cakeAddress,
            address(reg.pancakeswapRouter),
            type(uint256).max
        );
        for (uint i = 0; i < 10; i++) {
            vm.warp(block.timestamp + 60);
            vm.roll(block.number + 1);
            reg.pancakeswapRouter.exactInputSingle(
                IV3SwapRouter.ExactInputSingleParams({
                    tokenIn: wbnbAddress,
                    tokenOut: cakeAddress,
                    fee: poolFee,
                    recipient: donor,
                    amountIn: 250e18,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        }
        vm.stopPrank();
    }

    receive() external payable {}
}
