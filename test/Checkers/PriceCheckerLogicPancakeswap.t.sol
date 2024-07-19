// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {IV3SwapRouter} from "../../src/vault/interfaces/external/IV3SwapRouter.sol";

import {IPriceCheckerLogicBase} from "../../src/vault/logics/Checkers/PriceCheckerLogicBase.sol";
import {PriceCheckerLogicPancakeswap} from "../../src/vault/logics/Checkers/PriceCheckerLogicPancakeswap.sol";
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

    PriceCheckerLogicPancakeswap vault;
    address vaultOwner = makeAddr("VAULT_OWNER");
    address executor = makeAddr("EXECUTOR");

    IUniswapV3Pool pool =
        IUniswapV3Pool(0x133B3D95bAD5405d14d53473671200e9342896BF);
    uint24 poolFee;

    IUniswapV3Pool pool2 =
        IUniswapV3Pool(0xFC75f4E78bf71eD5066dB9ca771D4CcB7C1264E0);

    address cakeAddress = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82; // mainnet CAKE
    address wbnbAddress = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; // mainnet WBNB
    address donor = 0x8894E0a0c962CB723c1976a4421c95949bE2D4E3; // wallet for token airdrop

    function setUp() public {
        vm.createSelectFork(vm.envString("BNB_RPC_URL"));
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
        vault = PriceCheckerLogicPancakeswap(vaultFactory.deploy(1, 1));

        uint256 targetRate = reg.dittoOracle.consult(
            cakeAddress,
            1e18,
            wbnbAddress,
            poolFee,
            address(reg.pancakeswapFactory)
        );

        vm.startPrank(address(vault));
        vault.priceCheckerPancakeswapInitialize(
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
            cakeAddress,
            1e18,
            wbnbAddress,
            poolFee,
            address(reg.pancakeswapFactory)
        );

        (
            address token0,
            address token1,
            uint24 fee,
            uint256 targetRate,
            bool initialized
        ) = vault.pancakeswapGetLocalPriceCheckerStorage(
                priceCheckerStoragePointer
            );

        assertEq(token0, cakeAddress);
        assertEq(token1, wbnbAddress);
        assertEq(fee, poolFee);
        assertEq(targetRate, currentTargetRate);
        assertEq(initialized, true);

        (token0, token1, fee, targetRate, initialized) = vault
            .pancakeswapGetLocalPriceCheckerStorage(
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
        vault.priceCheckerPancakeswapInitialize(
            IUniswapV3Pool(address(0)),
            0,
            priceCheckerStoragePointer
        );
    }

    function test_timeChecker_shouldRevertIfNotInitialized() external {
        bytes32 storagePointer = keccak256("not initialized");

        vm.expectRevert(
            IPriceCheckerLogicBase.PriceChecker_NotInitialized.selector
        );
        vault.pancakeswapCheckGTTargetRate(storagePointer);
        vm.expectRevert(
            IPriceCheckerLogicBase.PriceChecker_NotInitialized.selector
        );
        vault.pancakeswapCheckGTETargetRate(storagePointer);
        vm.expectRevert(
            IPriceCheckerLogicBase.PriceChecker_NotInitialized.selector
        );
        vault.pancakeswapCheckLTTargetRate(storagePointer);
        vm.expectRevert(
            IPriceCheckerLogicBase.PriceChecker_NotInitialized.selector
        );
        vault.pancakeswapCheckLTETargetRate(storagePointer);

        vm.prank(vaultOwner);
        vm.expectRevert(
            IPriceCheckerLogicBase.PriceChecker_NotInitialized.selector
        );
        vault.pancakeswapChangeTokensAndFeePriceChecker(
            IUniswapV3Pool(address(0)),
            storagePointer
        );
        vm.prank(vaultOwner);
        vm.expectRevert(
            IPriceCheckerLogicBase.PriceChecker_NotInitialized.selector
        );
        vault.pancakeswapChangeTargetRate(123, storagePointer);
    }

    function test_priceChecker_checkGTTargetRate_shouldReturnFalse() external {
        assertFalse(
            vault.pancakeswapCheckGTTargetRate(priceCheckerStoragePointer)
        );
    }

    function test_priceChecker_checkGTTargetRate_shouldReturnTrue() external {
        _rateUp();

        assertTrue(
            vault.pancakeswapCheckGTTargetRate(priceCheckerStoragePointer)
        );
    }

    function test_priceChecker_checkGTETargetRate_shouldReturnTrue() external {
        assertTrue(
            vault.pancakeswapCheckGTETargetRate(priceCheckerStoragePointer)
        );
    }

    function test_priceChecker_checkGTETargetRate_shouldReturnFalse() external {
        _rateDown();

        assertFalse(
            vault.pancakeswapCheckGTETargetRate(priceCheckerStoragePointer)
        );
    }

    function test_priceChecker_checkLTTargetRate_shouldReturnFalse() external {
        assertFalse(
            vault.pancakeswapCheckLTTargetRate(priceCheckerStoragePointer)
        );
    }

    function test_priceChecker_checkLTTargetRate_shouldReturnTrue() external {
        _rateDown();

        assertTrue(
            vault.pancakeswapCheckLTTargetRate(priceCheckerStoragePointer)
        );
    }

    function test_priceChecker_checkLTETargetRate_shouldReturnTrue() external {
        assertTrue(
            vault.pancakeswapCheckLTETargetRate(priceCheckerStoragePointer)
        );
    }

    function test_priceChecker_checkLTETargetRate_shouldReturnFalse() external {
        _rateUp();

        assertFalse(
            vault.pancakeswapCheckLTETargetRate(priceCheckerStoragePointer)
        );
    }

    function test_priceChecker_changeTokensAndFeePriceChecker() external {
        vm.prank(vaultOwner);
        vault.pancakeswapChangeTokensAndFeePriceChecker(
            pool2,
            priceCheckerStoragePointer
        );

        (address token0, address token1, uint24 fee, , ) = vault
            .pancakeswapGetLocalPriceCheckerStorage(priceCheckerStoragePointer);

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
        vault.pancakeswapChangeTokensAndFeePriceChecker(
            pool2,
            priceCheckerStoragePointer
        );
    }

    function test_priceChecker_pancakeswapChangeTargetRate() external {
        vm.prank(vaultOwner);
        vault.pancakeswapChangeTargetRate(0, priceCheckerStoragePointer);

        (, , , uint256 targetRate, ) = vault
            .pancakeswapGetLocalPriceCheckerStorage(priceCheckerStoragePointer);

        assertEq(targetRate, 0);
    }

    function test_priceChecker_pancakeswapChangeTargetRate_accessControl()
        external
    {
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.pancakeswapChangeTargetRate(0, priceCheckerStoragePointer);
    }

    // --------------------

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

    // Rate down
    function _rateDown() internal {
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
                    tokenIn: cakeAddress,
                    tokenOut: wbnbAddress,
                    fee: poolFee,
                    recipient: donor,
                    amountIn: 50000e18,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        }
        vm.stopPrank();
    }
}
