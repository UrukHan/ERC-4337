// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {IV3SwapRouter} from "../../src/vault/interfaces/external/IV3SwapRouter.sol";

import {IPriceCheckerLogicBase} from "../../src/vault/logics/Checkers/PriceCheckerLogicBase.sol";
import {PriceCheckerLogicUniswap} from "../../src/vault/logics/Checkers/PriceCheckerLogicUniswap.sol";
import {AccessControlLogic} from "../../src/vault/logics/AccessControlLogic.sol";
import {BaseContract, Constants} from "../../src/vault/libraries/BaseContract.sol";
import {VaultFactory} from "../../src/VaultFactory.sol";
import {TransferHelper} from "../../src/vault/libraries/utils/TransferHelper.sol";

import {FullDeploy, Registry, VaultProxyAdmin} from "../../script/FullDeploy.s.sol";

contract PriceCheckerLogicTest is Test, FullDeploy {
    bool isTest = true;

    Registry.Contracts reg;

    bytes32 priceCheckerStoragePointer =
        keccak256("price checker storage pointer");

    PriceCheckerLogicUniswap vault;
    address vaultOwner = makeAddr("VAULT_OWNER");
    address executor = makeAddr("EXECUTOR");

    IUniswapV3Pool pool =
        IUniswapV3Pool(0x45dDa9cb7c25131DF268515131f647d726f50608);
    uint24 poolFee;

    IUniswapV3Pool pool2 =
        IUniswapV3Pool(0x3e31AB7f37c048FC6574189135D108df80F0ea26);

    address usdcAddress = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174; // mainnet USDC
    address wethAddress = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619; // mainnet WETH
    address donor = 0x55CAaBB0d2b704FD0eF8192A7E35D8837e678207; // wallet for token airdrop

    function setUp() public {
        vm.createSelectFork(vm.envString("POL_RPC_URL"));
        poolFee = pool.fee();

        reg = deploySystemContracts(
            isTest,
            Registry.contractsByChainId(block.chainid)
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

        vm.prank(vaultOwner);
        vault = PriceCheckerLogicUniswap(vaultFactory.deploy(1, 1));

        uint256 targetRate = reg.dittoOracle.consult(
            usdcAddress,
            1e6,
            wethAddress,
            poolFee,
            address(reg.uniswapFactory)
        );

        vm.startPrank(address(vault));
        vault.priceCheckerUniswapInitialize(
            pool,
            targetRate,
            priceCheckerStoragePointer
        );

        AccessControlLogic(address(vault)).grantRole(
            Constants.EXECUTOR_ROLE,
            executor
        );

        vm.stopPrank();
    }

    function test_priceChecker_shouldReturnCorrectLocalState() external {
        uint256 currentTargetRate = reg.dittoOracle.consult(
            usdcAddress,
            1e6,
            wethAddress,
            poolFee,
            address(reg.uniswapFactory)
        );

        (
            address token0,
            address token1,
            uint24 fee,
            uint256 targetRate,
            bool initialized
        ) = vault.uniswapGetLocalPriceCheckerStorage(
                priceCheckerStoragePointer
            );

        assertEq(token0, usdcAddress);
        assertEq(token1, wethAddress);
        assertEq(fee, poolFee);
        assertEq(targetRate, currentTargetRate);
        assertEq(initialized, true);

        (token0, token1, fee, targetRate, initialized) = vault
            .uniswapGetLocalPriceCheckerStorage(
                keccak256("not initialized local storage")
            );

        assertEq(token0, address(0));
        assertEq(token1, address(0));
        assertEq(fee, 0);
        assertEq(targetRate, 0);
        assertEq(initialized, false);
    }

    function test_priceChecker_cannotBeInitalizedMultipleTimes() external {
        vm.prank(address(vault));
        vm.expectRevert(
            IPriceCheckerLogicBase.PriceChecker_AlreadyInitialized.selector
        );
        vault.priceCheckerUniswapInitialize(
            IUniswapV3Pool(address(0)),
            0,
            priceCheckerStoragePointer
        );
    }

    function test_timeChecker_shouldRevertIfNotInitialized() external {
        bytes32 storagePointer = keccak256("not initialized local storage");

        vm.expectRevert(
            IPriceCheckerLogicBase.PriceChecker_NotInitialized.selector
        );
        vault.uniswapCheckGTTargetRate(storagePointer);
        vm.expectRevert(
            IPriceCheckerLogicBase.PriceChecker_NotInitialized.selector
        );
        vault.uniswapCheckGTETargetRate(storagePointer);
        vm.expectRevert(
            IPriceCheckerLogicBase.PriceChecker_NotInitialized.selector
        );
        vault.uniswapCheckLTTargetRate(storagePointer);
        vm.expectRevert(
            IPriceCheckerLogicBase.PriceChecker_NotInitialized.selector
        );
        vault.uniswapCheckLTETargetRate(storagePointer);

        vm.prank(vaultOwner);
        vm.expectRevert(
            IPriceCheckerLogicBase.PriceChecker_NotInitialized.selector
        );
        vault.uniswapChangeTokensAndFeePriceChecker(
            IUniswapV3Pool(address(0)),
            storagePointer
        );
        vm.prank(vaultOwner);
        vm.expectRevert(
            IPriceCheckerLogicBase.PriceChecker_NotInitialized.selector
        );
        vault.uniswapChangeTargetRate(123, storagePointer);
    }

    function test_priceChecker_checkGTTargetRate_shouldReturnFalse() external {
        assertFalse(vault.uniswapCheckGTTargetRate(priceCheckerStoragePointer));
    }

    function uniswapCest_priceChecker_checkGTTargetRate_shouldReturnTrue()
        external
    {
        _rateUp();

        assertTrue(vault.uniswapCheckGTTargetRate(priceCheckerStoragePointer));
    }

    function test_priceChecker_checkGTETargetRate_shouldReturnTrue() external {
        assertTrue(vault.uniswapCheckGTETargetRate(priceCheckerStoragePointer));
    }

    function test_priceChecker_checkGTETargetRate_shouldReturnFalse() external {
        _rateDown();

        assertFalse(
            vault.uniswapCheckGTETargetRate(priceCheckerStoragePointer)
        );
    }

    function test_priceChecker_checkLTTargetRate_shouldReturnFalse() external {
        assertFalse(vault.uniswapCheckLTTargetRate(priceCheckerStoragePointer));
    }

    function test_priceChecker_checkLTTargetRate_shouldReturnTrue() external {
        _rateDown();

        assertTrue(vault.uniswapCheckLTTargetRate(priceCheckerStoragePointer));
    }

    function test_priceChecker_checkLTETargetRate_shouldReturnTrue() external {
        assertTrue(vault.uniswapCheckLTETargetRate(priceCheckerStoragePointer));
    }

    function test_priceChecker_checkLTETargetRate_shouldReturnFalse() external {
        _rateUp();

        assertFalse(
            vault.uniswapCheckLTETargetRate(priceCheckerStoragePointer)
        );
    }

    function test_priceChecker_changeTokensAndFeePriceChecker() external {
        vm.prank(vaultOwner);
        vault.uniswapChangeTokensAndFeePriceChecker(
            pool2,
            priceCheckerStoragePointer
        );

        (address token0, address token1, uint24 fee, , ) = vault
            .uniswapGetLocalPriceCheckerStorage(priceCheckerStoragePointer);

        assertEq(token0, pool2.token0());
        assertEq(token1, pool2.token1());
        assertEq(fee, pool2.fee());
    }

    function test_priceChecker_changeTokensAndFeePriceChecker_accessControl()
        external
    {
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.uniswapChangeTokensAndFeePriceChecker(
            pool2,
            priceCheckerStoragePointer
        );
    }

    function test_priceChecker_uniswapChangeTargetRate() external {
        vm.prank(vaultOwner);
        vault.uniswapChangeTargetRate(0, priceCheckerStoragePointer);

        (, , , uint256 targetRate, ) = vault.uniswapGetLocalPriceCheckerStorage(
            priceCheckerStoragePointer
        );

        assertEq(targetRate, 0);
    }

    function test_priceChecker_uniswapChangeTargetRate_accessControl()
        external
    {
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.uniswapChangeTargetRate(0, priceCheckerStoragePointer);
    }

    // --------------------
    // Rate down
    function _rateDown() internal {
        vm.startPrank(donor);
        TransferHelper.safeApprove(
            wethAddress,
            address(reg.uniswapRouter),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            usdcAddress,
            address(reg.uniswapRouter),
            type(uint256).max
        );
        for (uint i = 0; i < 10; i++) {
            vm.warp(block.timestamp + 60);
            vm.roll(block.number + 1);
            reg.uniswapRouter.exactInputSingle(
                IV3SwapRouter.ExactInputSingleParams({
                    tokenIn: usdcAddress,
                    tokenOut: wethAddress,
                    fee: poolFee,
                    recipient: donor,
                    amountIn: 25000e6,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        }
        vm.stopPrank();
    }

    // Rate up
    function _rateUp() internal {
        vm.startPrank(donor);
        TransferHelper.safeApprove(
            wethAddress,
            address(reg.uniswapRouter),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            usdcAddress,
            address(reg.uniswapRouter),
            type(uint256).max
        );
        for (uint i = 0; i < 10; i++) {
            vm.warp(block.timestamp + 60);
            vm.roll(block.number + 1);
            reg.uniswapRouter.exactInputSingle(
                IV3SwapRouter.ExactInputSingleParams({
                    tokenIn: wethAddress,
                    tokenOut: usdcAddress,
                    fee: poolFee,
                    recipient: donor,
                    amountIn: 25e18,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        }
        vm.stopPrank();
    }
}
