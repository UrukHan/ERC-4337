// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {IV3SwapRouter} from "../../src/vault/interfaces/external/IV3SwapRouter.sol";
import {IPriceDifferenceCheckerLogicBase} from "../../src/vault/logics/Checkers/PriceDifferenceCheckerLogicBase.sol";
import {PriceDifferenceCheckerLogicPancakeswap} from "../../src/vault/logics/Checkers/PriceDifferenceCheckerLogicPancakeswap.sol";
import {AccessControlLogic} from "../../src/vault/logics/AccessControlLogic.sol";
import {BaseContract, Constants} from "../../src/vault/libraries/BaseContract.sol";
import {VaultFactory} from "../../src/VaultFactory.sol";
import {TransferHelper} from "../../src/vault/libraries/utils/TransferHelper.sol";

import {FullDeploy, Registry, VaultProxyAdmin} from "../../script/FullDeploy.s.sol";

contract PriceDifferenceCheckerLogicTest is Test, FullDeploy {
    bool isTest = true;

    Registry.Contracts reg;

    bytes32 priceDifferentCheckerStoragePointerRateUp =
        keccak256("price different checker storage pointer 1");
    bytes32 priceDifferentCheckerStoragePointerRateDown =
        keccak256("price different checker storage pointer 2");

    PriceDifferenceCheckerLogicPancakeswap vault;
    address vaultOwner = makeAddr("VAULT_OWNER");
    address executor = makeAddr("EXECUTOR");
    address user = makeAddr("USER");

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
        vault = PriceDifferenceCheckerLogicPancakeswap(
            vaultFactory.deploy(1, 1)
        );

        vm.startPrank(address(vault));
        vault.priceDifferenceCheckerPancakeswapInitialize(
            pool,
            1001,
            priceDifferentCheckerStoragePointerRateUp
        );

        vault.priceDifferenceCheckerPancakeswapInitialize(
            pool,
            999,
            priceDifferentCheckerStoragePointerRateDown
        );

        AccessControlLogic(address(vault)).grantRole(
            Constants.EXECUTOR_ROLE,
            executor
        );

        vm.stopPrank();
    }

    function test_priceDifferenceChecker_shouldReturnCorrectLocalState()
        external
    {
        uint256 currentRate = reg.dittoOracle.consult(
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
            uint24 percentageDeviation_E3,
            uint256 lastCheckPrice,
            bool initialized
        ) = vault.pancakeswapGetLocalPriceDifferenceCheckerStorage(
                priceDifferentCheckerStoragePointerRateUp
            );

        assertEq(token0, cakeAddress);
        assertEq(token1, wbnbAddress);
        assertEq(fee, poolFee);
        assertEq(percentageDeviation_E3, 1001);
        assertEq(lastCheckPrice, currentRate);
        assertEq(initialized, true);

        (
            token0,
            token1,
            fee,
            percentageDeviation_E3,
            lastCheckPrice,
            initialized
        ) = vault.pancakeswapGetLocalPriceDifferenceCheckerStorage(
            priceDifferentCheckerStoragePointerRateDown
        );

        assertEq(token0, cakeAddress);
        assertEq(token1, wbnbAddress);
        assertEq(fee, poolFee);
        assertEq(percentageDeviation_E3, 999);
        assertEq(lastCheckPrice, currentRate);
        assertEq(initialized, true);

        (
            token0,
            token1,
            fee,
            percentageDeviation_E3,
            lastCheckPrice,
            initialized
        ) = vault.pancakeswapGetLocalPriceDifferenceCheckerStorage(
            keccak256("not initialized local storage")
        );
        assertEq(token0, address(0));
        assertEq(token1, address(0));
        assertEq(fee, 0);
        assertEq(percentageDeviation_E3, 0);
        assertEq(lastCheckPrice, 0);
        assertEq(initialized, false);
    }

    function test_priceDifferenceChecker_cannotBeInitalizedMultipleTimes()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert(
            IPriceDifferenceCheckerLogicBase
                .PriceDifferenceChecker_AlreadyInitialized
                .selector
        );
        vault.priceDifferenceCheckerPancakeswapInitialize(
            pool2,
            1001,
            priceDifferentCheckerStoragePointerRateUp
        );
    }

    function test_priceDifferenceChecker_shouldRevertIfNotInitialized()
        external
    {
        bytes32 storagePointer = keccak256("not initialized local storage");

        vm.prank(address(vault));
        vm.expectRevert(
            IPriceDifferenceCheckerLogicBase
                .PriceDifferenceChecker_NotInitialized
                .selector
        );
        vault.pancakeswapCheckPriceDifference(storagePointer);

        vm.prank(vaultOwner);
        vm.expectRevert(
            IPriceDifferenceCheckerLogicBase
                .PriceDifferenceChecker_NotInitialized
                .selector
        );
        vault.pancakeswapCheckPriceDifferenceView(storagePointer);

        vm.prank(vaultOwner);
        vm.expectRevert(
            IPriceDifferenceCheckerLogicBase
                .PriceDifferenceChecker_NotInitialized
                .selector
        );
        vault.pancakeswapChangeTokensAndFeePriceDiffChecker(
            pool,
            storagePointer
        );

        vm.prank(vaultOwner);
        vm.expectRevert(
            IPriceDifferenceCheckerLogicBase
                .PriceDifferenceChecker_NotInitialized
                .selector
        );
        vault.pancakeswapChangePercentageDeviationE3(123, storagePointer);
    }

    function test_priceDifferenceChecker_pancakeswapCheckPriceDifference_shouldReturnFalse()
        external
    {
        (, , , , uint256 lastCheckPriceBefore, ) = vault
            .pancakeswapGetLocalPriceDifferenceCheckerStorage(
                priceDifferentCheckerStoragePointerRateUp
            );

        vm.prank(address(vault));
        assertFalse(
            vault.pancakeswapCheckPriceDifference(
                priceDifferentCheckerStoragePointerRateUp
            )
        );

        (, , , , uint256 lastCheckPriceAfter, ) = vault
            .pancakeswapGetLocalPriceDifferenceCheckerStorage(
                priceDifferentCheckerStoragePointerRateUp
            );

        assertEq(lastCheckPriceBefore, lastCheckPriceAfter);
    }

    function test_priceDifferenceChecker_pancakeswapCheckPriceDifference_shouldReturnTrue_rateUp()
        external
    {
        // up
        (, , , , uint256 lastCheckPriceBefore, ) = vault
            .pancakeswapGetLocalPriceDifferenceCheckerStorage(
                priceDifferentCheckerStoragePointerRateUp
            );

        _rateUp();

        vm.prank(address(vault));
        assertTrue(
            vault.pancakeswapCheckPriceDifference(
                priceDifferentCheckerStoragePointerRateUp
            )
        );

        uint256 currentRate = reg.dittoOracle.consult(
            cakeAddress,
            1e18,
            wbnbAddress,
            poolFee,
            address(reg.pancakeswapFactory)
        );
        (, , , , uint256 lastCheckPriceAfter, ) = vault
            .pancakeswapGetLocalPriceDifferenceCheckerStorage(
                priceDifferentCheckerStoragePointerRateUp
            );

        assertGt(lastCheckPriceAfter, lastCheckPriceBefore);
        assertEq(lastCheckPriceAfter, currentRate);
    }

    function test_priceDifferenceChecker_pancakeswapCheckPriceDifference_shouldReturnTrue_rateDown()
        external
    {
        // down
        (, , , , uint256 lastCheckPriceBefore, ) = vault
            .pancakeswapGetLocalPriceDifferenceCheckerStorage(
                priceDifferentCheckerStoragePointerRateDown
            );

        _rateDown();

        vm.prank(address(vault));
        assertTrue(
            vault.pancakeswapCheckPriceDifference(
                priceDifferentCheckerStoragePointerRateDown
            )
        );

        uint256 currentRate = reg.dittoOracle.consult(
            cakeAddress,
            1e18,
            wbnbAddress,
            poolFee,
            address(reg.pancakeswapFactory)
        );
        (, , , , uint256 lastCheckPriceAfter, ) = vault
            .pancakeswapGetLocalPriceDifferenceCheckerStorage(
                priceDifferentCheckerStoragePointerRateDown
            );

        assertLt(lastCheckPriceAfter, lastCheckPriceBefore);
        assertEq(lastCheckPriceAfter, currentRate);
    }

    function test_priceDifferenceChecker_pancakeswapCheckPriceDifference_accessControl()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.pancakeswapCheckPriceDifference(
            priceDifferentCheckerStoragePointerRateDown
        );

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.pancakeswapCheckPriceDifference(
            priceDifferentCheckerStoragePointerRateDown
        );

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.pancakeswapCheckPriceDifference(
            priceDifferentCheckerStoragePointerRateUp
        );
    }

    function test_priceDifferenceChecker_pancakeswapCheckPriceDifferenceView_shouldReturnFalse()
        external
    {
        assertFalse(
            vault.pancakeswapCheckPriceDifferenceView(
                priceDifferentCheckerStoragePointerRateUp
            )
        );
    }

    function test_priceDifferenceChecker_pancakeswapCheckPriceDifferenceView_shouldReturnTrue_rateUp()
        external
    {
        _rateUp();

        assertTrue(
            vault.pancakeswapCheckPriceDifferenceView(
                priceDifferentCheckerStoragePointerRateUp
            )
        );
    }

    function test_priceDifferenceChecker_pancakeswapCheckPriceDifferenceView_shouldReturnTrue_rateDown()
        external
    {
        _rateDown();

        assertTrue(
            vault.pancakeswapCheckPriceDifferenceView(
                priceDifferentCheckerStoragePointerRateDown
            )
        );
    }

    function test_priceDifferenceChecker_pancakeswapChangeTokensAndFeePriceDiffChecker()
        external
    {
        vm.prank(vaultOwner);
        vault.pancakeswapChangeTokensAndFeePriceDiffChecker(
            pool2,
            priceDifferentCheckerStoragePointerRateUp
        );

        (address token0, address token1, uint24 fee, , , ) = vault
            .pancakeswapGetLocalPriceDifferenceCheckerStorage(
                priceDifferentCheckerStoragePointerRateUp
            );

        assertEq(token0, pool2.token0());
        assertEq(token1, pool2.token1());
        assertEq(fee, pool2.fee());
    }

    function test_priceDifferenceChecker_pancakeswapChangeTokensAndFeePriceDiffChecker_accessControl()
        external
    {
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.pancakeswapChangeTokensAndFeePriceDiffChecker(
            pool2,
            priceDifferentCheckerStoragePointerRateUp
        );

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.pancakeswapChangeTokensAndFeePriceDiffChecker(
            pool2,
            priceDifferentCheckerStoragePointerRateUp
        );
    }

    function test_priceDifferenceChecker_pancakeswapChangePercentageDeviationE3()
        external
    {
        vm.prank(vaultOwner);
        vault.pancakeswapChangePercentageDeviationE3(
            1010,
            priceDifferentCheckerStoragePointerRateUp
        );

        (, , , uint24 percentageDeviation_E3, , ) = vault
            .pancakeswapGetLocalPriceDifferenceCheckerStorage(
                priceDifferentCheckerStoragePointerRateUp
            );

        assertEq(percentageDeviation_E3, 1010);
    }

    function test_priceDifferenceChecker_pancakeswapChangePercentageDeviationE3_shouldRevertInvalidPercentage()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            IPriceDifferenceCheckerLogicBase
                .PriceDifferenceChecker_InvalidPercentageDeviation
                .selector
        );
        vault.pancakeswapChangePercentageDeviationE3(
            2001,
            priceDifferentCheckerStoragePointerRateUp
        );
    }

    function test_priceDifferenceChecker_pancakeswapChangePercentageDeviationE3_accessControl()
        external
    {
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.pancakeswapChangePercentageDeviationE3(
            1000,
            priceDifferentCheckerStoragePointerRateUp
        );

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.pancakeswapChangePercentageDeviationE3(
            1000,
            priceDifferentCheckerStoragePointerRateUp
        );
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
                    amountIn: 300e18,
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
                    amountIn: 100000e18,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        }
        vm.stopPrank();
    }
}
