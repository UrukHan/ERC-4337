// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ProtocolFees} from "../../src/ProtocolFees.sol";

import {VaultFactory} from "../../src/VaultFactory.sol";
import {BaseContract} from "../../src/vault/libraries/BaseContract.sol";
import {ExecutionLogic, IExecutionLogic} from "../../src/vault/logics/ExecutionLogic.sol";
import {VaultLogic} from "../../src/vault/logics/VaultLogic.sol";
import {UniswapLogic} from "../../src/vault/logics/OurLogic/dexAutomation/UniswapLogic.sol";

import {TransferHelper} from "../../src/vault/libraries/utils/TransferHelper.sol";

import {FullDeploy, Registry, VaultProxyAdmin} from "../../script/FullDeploy.s.sol";

contract ExecutionLogicTest is Test, FullDeploy {
    bool isTest = true;

    Registry.Contracts reg;

    address vault;

    IUniswapV3Pool pool =
        IUniswapV3Pool(0x45dDa9cb7c25131DF268515131f647d726f50608);
    uint24 poolFee;

    // mainnet USDC
    address usdcAddress = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    // mainnet WETH
    address wethAddress = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    // mainnet WMATIC
    address wmaticAddress = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address donor = 0x55CAaBB0d2b704FD0eF8192A7E35D8837e678207; // wallet for token airdrop

    address vaultOwner = makeAddr("VAULT_OWNER");
    address executor = makeAddr("EXECUTOR");

    uint256 nftId;

    function setUp() external {
        vm.createSelectFork(vm.envString("POL_RPC_URL"));
        vm.txGasPrice(80000000000);

        poolFee = pool.fee();

        vm.startPrank(donor);
        TransferHelper.safeTransfer(usdcAddress, vaultOwner, 20000e6);
        TransferHelper.safeTransfer(wethAddress, vaultOwner, 10e18);
        vm.stopPrank();

        reg = deploySystemContracts(
            isTest,
            Registry.contractsByChainId(block.chainid)
        );

        reg.protocolFees = new ProtocolFees(vaultOwner);
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

        vm.deal(vault, 2 ether);
        vm.deal(vaultOwner, 3 ether);

        TransferHelper.safeApprove(usdcAddress, vault, type(uint256).max);
        TransferHelper.safeApprove(wethAddress, vault, type(uint256).max);

        (, int24 currentTick, , , , , ) = pool.slot0();
        int24 minTick = ((currentTick - 4000) / 60) * 60;
        int24 maxTick = ((currentTick + 4000) / 60) * 60;

        uint256 RTarget = reg.lens.dexLogicLens.getTargetRE18ForTickRange(
            minTick,
            maxTick,
            pool
        );
        uint160 sqrtPriceX96 = reg.lens.dexLogicLens.getCurrentSqrtRatioX96(
            pool
        );

        uint256 wethAmount = reg.lens.dexLogicLens.token1AmountForTargetRE18(
            sqrtPriceX96,
            500e6,
            1e18,
            RTarget,
            poolFee
        );

        uint256 usdcAmount = reg.lens.dexLogicLens.token0AmountForTargetRE18(
            sqrtPriceX96,
            wethAmount,
            RTarget
        );

        VaultLogic(vault).depositERC20(wethAddress, wethAmount, vaultOwner);
        VaultLogic(vault).depositERC20(usdcAddress, usdcAmount, vaultOwner);
        vm.stopPrank();

        vm.prank(vault);
        // mint new nft for tests
        nftId = UniswapLogic(vault).uniswapMintNft(
            pool,
            ((currentTick - 4000) / 60) * 60,
            ((currentTick + 4000) / 60) * 60,
            usdcAmount,
            wethAmount,
            false,
            true,
            1e18
        );
    }

    function test_executionLogic_onERC721Received_shouldReturnSelector()
        external
    {
        assertEq(
            ExecutionLogic.onERC721Received.selector,
            ExecutionLogic(vault).onERC721Received(
                address(0),
                address(0),
                0,
                bytes("")
            )
        );
    }

    function test_executionLogic_execute_canExecuteArbitraryData() external {
        vm.startPrank(vault);

        bytes memory returnData = IExecutionLogic(vault).execute(
            usdcAddress,
            0,
            abi.encodeWithSignature("symbol()")
        );
        assertEq(
            abi.decode(returnData, (string)),
            IERC20Metadata(usdcAddress).symbol()
        );

        returnData = IExecutionLogic(vault).execute(
            usdcAddress,
            0,
            abi.encodeWithSignature("decimals()")
        );
        assertEq(
            abi.decode(returnData, (uint256)),
            IERC20Metadata(usdcAddress).decimals()
        );

        returnData = IExecutionLogic(vault).execute(
            usdcAddress,
            0,
            abi.encodeWithSignature("name()")
        );
        assertEq(
            abi.decode(returnData, (string)),
            IERC20Metadata(usdcAddress).name()
        );

        vm.stopPrank();
    }

    function test_executionLogic_execute_executeWithNativeAmount() external {
        vm.startPrank(vault);

        bytes memory returnData = IExecutionLogic(vault).execute(
            wmaticAddress,
            0,
            abi.encodeWithSignature("balanceOf(address)", address(vault))
        );

        assertEq(abi.decode(returnData, (uint256)), 0);

        IExecutionLogic(vault).execute(
            wmaticAddress,
            1 ether,
            abi.encodeWithSignature("deposit()")
        );

        returnData = IExecutionLogic(vault).execute(
            wmaticAddress,
            0,
            abi.encodeWithSignature("balanceOf(address)", address(vault))
        );

        assertEq(abi.decode(returnData, (uint256)), 1 ether);

        IExecutionLogic(vault).execute(
            wmaticAddress,
            1 ether,
            abi.encodeWithSignature("deposit()")
        );

        returnData = IExecutionLogic(vault).execute(
            wmaticAddress,
            0,
            abi.encodeWithSignature("balanceOf(address)", address(vault))
        );

        assertEq(abi.decode(returnData, (uint256)), 2 ether);

        vm.stopPrank();
    }

    function test_executionLogic_execute_shouldRevertIfTargetIsVaultAddress()
        external
    {
        vm.prank(vault);
        vm.expectRevert(
            IExecutionLogic
                .ExecutionLogic_ExecuteTargetCannotBeAddressThis
                .selector
        );
        IExecutionLogic(vault).execute(address(vault), 0, bytes(""));
    }

    function test_executionLogic_execute_shouldRevertIfExeternalCallReverted()
        external
    {
        vm.prank(vault);
        bytes memory data = abi.encodeWithSignature(
            "transferFrom(address,address,uint256)",
            address(this),
            address(vault),
            1 ether
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutionLogic.ExecutionLogic_ExecuteCallReverted.selector,
                usdcAddress,
                data
            )
        );
        IExecutionLogic(vault).execute(usdcAddress, 0, data);
    }

    function test_executionLogic_execute_accessControl() external {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        IExecutionLogic(vault).execute(
            usdcAddress,
            0,
            abi.encodeWithSignature("balanceOf(address)", address(this))
        );

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        IExecutionLogic(vault).execute(
            usdcAddress,
            0,
            abi.encodeWithSignature("balanceOf(address)", address(this))
        );
    }

    function test_executionLogic_multicall() external {
        (, int24 currentTick, , , , , ) = pool.slot0();

        vm.startPrank(vaultOwner);

        bytes[] memory data = new bytes[](6);
        data[0] = abi.encodeCall(
            VaultLogic.depositERC20,
            (usdcAddress, 2500e6, vaultOwner)
        );
        data[1] = abi.encodeCall(
            VaultLogic.depositERC20,
            (wethAddress, 1e18, vaultOwner)
        );

        address[] memory tokens = new address[](2);
        uint24[] memory poolFees = new uint24[](1);
        tokens[0] = usdcAddress;
        tokens[1] = wethAddress;
        poolFees[0] = 500;

        data[2] = abi.encodeCall(
            UniswapLogic.uniswapSwapExactInput,
            (tokens, poolFees, 1000e6, false, false, 0.1e18)
        );

        data[3] = abi.encodeCall(
            UniswapLogic.uniswapAddLiquidity,
            (nftId, 750e6, 0.4e18, false, true, 0.1e18)
        );

        data[4] = abi.encodeCall(
            UniswapLogic.uniswapMintNft,
            (
                pool,
                ((currentTick - 2000) / 60) * 60,
                ((currentTick + 2000) / 60) * 60,
                750e6,
                0.6e18,
                false,
                true,
                0.1e18
            )
        );

        data[5] = abi.encodeCall(
            IExecutionLogic.execute,
            (wmaticAddress, 1 ether, abi.encodeWithSignature("deposit()"))
        );

        IExecutionLogic(vault).multicall{value: 2 ether}(data);

        vm.stopPrank();
    }

    function test_executionLogic_multicall_shouldRevertIfOneCallReverts()
        external
    {
        vm.startPrank(vaultOwner);

        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeCall(
            IExecutionLogic.execute,
            (wmaticAddress, 1 ether, abi.encodeWithSignature("deposit()"))
        );
        data[1] = abi.encodeCall(
            IExecutionLogic.execute,
            (wmaticAddress, 1 ether, abi.encodeWithSignature("deposit()"))
        );
        data[2] = abi.encodeCall(
            IExecutionLogic.execute,
            (
                usdcAddress,
                0,
                abi.encodeWithSignature(
                    "transferFrom(address,address,uint256)",
                    address(this),
                    address(vault),
                    1 ether
                )
            )
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutionLogic.ExecutionLogic_ExecuteCallReverted.selector,
                usdcAddress,
                abi.encodeWithSignature(
                    "transferFrom(address,address,uint256)",
                    address(this),
                    address(vault),
                    1 ether
                )
            )
        );
        IExecutionLogic(vault).multicall{value: 1 ether}(data);

        vm.stopPrank();
    }

    function test_executionLogic_multicall_accessControl() external {
        bytes[] memory data = new bytes[](1);

        vm.prank(executor);
        data[0] = abi.encodeCall(
            VaultLogic.withdrawNative,
            (executor, address(vault).balance)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        IExecutionLogic(vault).multicall(data);
    }

    function test_executionLogic_taxedMulticall() external {
        (, int24 currentTick, , , , , ) = pool.slot0();

        vm.startPrank(vaultOwner);

        bytes[] memory data = new bytes[](6);
        data[0] = abi.encodeCall(
            VaultLogic.depositERC20,
            (usdcAddress, 2500e6, vaultOwner)
        );
        data[1] = abi.encodeCall(
            VaultLogic.depositERC20,
            (wethAddress, 1e18, vaultOwner)
        );

        address[] memory tokens = new address[](2);
        uint24[] memory poolFees = new uint24[](1);
        tokens[0] = usdcAddress;
        tokens[1] = wethAddress;
        poolFees[0] = 500;

        data[2] = abi.encodeCall(
            UniswapLogic.uniswapSwapExactInput,
            (tokens, poolFees, 1000e6, false, false, 0.1e18)
        );

        data[3] = abi.encodeCall(
            UniswapLogic.uniswapAddLiquidity,
            (nftId, 750e6, 0.4e18, false, true, 0.1e18)
        );

        data[4] = abi.encodeCall(
            UniswapLogic.uniswapMintNft,
            (
                pool,
                ((currentTick - 2000) / 60) * 60,
                ((currentTick + 2000) / 60) * 60,
                750e6,
                0.6e18,
                false,
                true,
                0.1e18
            )
        );

        data[5] = abi.encodeCall(
            IExecutionLogic.execute,
            (wmaticAddress, 1 ether, abi.encodeWithSignature("deposit()"))
        );

        IExecutionLogic(vault).taxedMulticall{value: 2 ether}(data);

        vm.stopPrank();
    }

    function test_executionLogic_taxedMulticall_shouldRevertIfOneCallReverts()
        external
    {
        vm.startPrank(vaultOwner);

        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeCall(
            IExecutionLogic.execute,
            (wmaticAddress, 1 ether, abi.encodeWithSignature("deposit()"))
        );
        data[1] = abi.encodeCall(
            IExecutionLogic.execute,
            (wmaticAddress, 1 ether, abi.encodeWithSignature("deposit()"))
        );
        data[2] = abi.encodeCall(
            IExecutionLogic.execute,
            (
                usdcAddress,
                0,
                abi.encodeWithSignature(
                    "transferFrom(address,address,uint256)",
                    address(this),
                    address(vault),
                    1 ether
                )
            )
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                IExecutionLogic.ExecutionLogic_ExecuteCallReverted.selector,
                usdcAddress,
                abi.encodeWithSignature(
                    "transferFrom(address,address,uint256)",
                    address(this),
                    address(vault),
                    1 ether
                )
            )
        );
        IExecutionLogic(vault).taxedMulticall{value: 1 ether}(data);

        vm.stopPrank();
    }

    function test_executionLogic_taxedMulticall_accessControl() external {
        vm.prank(executor);
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(
            VaultLogic.withdrawNative,
            (executor, address(vault).balance)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        IExecutionLogic(vault).taxedMulticall(data);
    }

    function test_executionLogic_taxedMulticall_instantFees_woTreasury()
        external
    {
        address treasury = makeAddr("treasury");

        assertEq(treasury.balance, 0);

        vm.prank(vaultOwner);
        reg.protocolFees.setInstantFees(1e18, 1e18);

        vm.prank(vaultOwner);
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(
            VaultLogic.withdrawNative,
            (vaultOwner, address(vault).balance)
        );

        IExecutionLogic(vault).taxedMulticall(data);

        assertEq(treasury.balance, 0);
    }

    function test_executionLogic_taxedMulticall_instantFees_withTreasuryShouldRevertIfNotEnoughFunds()
        external
    {
        address treasury = makeAddr("treasury");

        assertEq(treasury.balance, 0);

        vm.prank(vaultOwner);
        reg.protocolFees.setInstantFees(1e18, 1e18);
        vm.prank(vaultOwner);
        reg.protocolFees.setTreasury(treasury);

        vm.prank(vaultOwner);
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(
            VaultLogic.withdrawNative,
            (vaultOwner, address(vault).balance)
        );

        vm.expectRevert(
            TransferHelper.TransferHelper_SafeTransferNativeError.selector
        );

        IExecutionLogic(vault).taxedMulticall(data);
    }

    function test_executionLogic_taxedMulticall_instantFees_withTreasury()
        external
    {
        address treasury = makeAddr("treasury");

        assertEq(treasury.balance, 0);

        vm.prank(vaultOwner);
        reg.protocolFees.setInstantFees(1e18, 1e18);
        vm.prank(vaultOwner);
        reg.protocolFees.setTreasury(treasury);

        vm.prank(vaultOwner);
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(
            VaultLogic.withdrawNative,
            (vaultOwner, 0.5e18)
        );

        IExecutionLogic(vault).taxedMulticall(data);

        assertGt(treasury.balance, 1e18);
    }
}
