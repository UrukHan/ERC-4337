// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {IV3SwapRouter} from "../../src/vault/interfaces/external/IV3SwapRouter.sol";
import {IPriceDifferenceCheckerLogicBase} from "../../src/vault/logics/Checkers/PriceDifferenceCheckerLogicBase.sol";
import {PriceDifferenceCheckerLogicUniswap} from "../../src/vault/logics/Checkers/PriceDifferenceCheckerLogicUniswap.sol";
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

    PriceDifferenceCheckerLogicUniswap vault;
    address vaultOwner = makeAddr("VAULT_OWNER");
    address executor = makeAddr("EXECUTOR");
    address user = makeAddr("USER");

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
        vault = PriceDifferenceCheckerLogicUniswap(vaultFactory.deploy(1, 1));

        vm.startPrank(address(vault));
        vault.priceDifferenceCheckerUniswapInitialize(
            pool,
            1001,
            priceDifferentCheckerStoragePointerRateUp
        );

        vault.priceDifferenceCheckerUniswapInitialize(
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
            uint24 percentageDeviation_E3,
            uint256 lastCheckPrice,
            bool initialized
        ) = vault.uniswapGetLocalPriceDifferenceCheckerStorage(
                priceDifferentCheckerStoragePointerRateUp
            );

        assertEq(token0, usdcAddress);
        assertEq(token1, wethAddress);
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
        ) = vault.uniswapGetLocalPriceDifferenceCheckerStorage(
            priceDifferentCheckerStoragePointerRateDown
        );

        assertEq(token0, usdcAddress);
        assertEq(token1, wethAddress);
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
        ) = vault.uniswapGetLocalPriceDifferenceCheckerStorage(
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
        vault.priceDifferenceCheckerUniswapInitialize(
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
        vault.uniswapCheckPriceDifference(storagePointer);

        vm.expectRevert(
            IPriceDifferenceCheckerLogicBase
                .PriceDifferenceChecker_NotInitialized
                .selector
        );
        vault.uniswapCheckPriceDifferenceView(storagePointer);

        vm.prank(vaultOwner);
        vm.expectRevert(
            IPriceDifferenceCheckerLogicBase
                .PriceDifferenceChecker_NotInitialized
                .selector
        );
        vault.uniswapChangeTokensAndFeePriceDiffChecker(pool, storagePointer);

        vm.prank(vaultOwner);
        vm.expectRevert(
            IPriceDifferenceCheckerLogicBase
                .PriceDifferenceChecker_NotInitialized
                .selector
        );
        vault.uniswapChangePercentageDeviationE3(123, storagePointer);
    }

    function test_priceDifferenceChecker_uniswapCheckPriceDifference_shouldReturnFalse()
        external
    {
        (, , , , uint256 lastCheckPriceBefore, ) = vault
            .uniswapGetLocalPriceDifferenceCheckerStorage(
                priceDifferentCheckerStoragePointerRateUp
            );

        vm.prank(address(vault));
        assertFalse(
            vault.uniswapCheckPriceDifference(
                priceDifferentCheckerStoragePointerRateUp
            )
        );

        (, , , , uint256 lastCheckPriceAfter, ) = vault
            .uniswapGetLocalPriceDifferenceCheckerStorage(
                priceDifferentCheckerStoragePointerRateUp
            );

        assertEq(lastCheckPriceBefore, lastCheckPriceAfter);
    }

    function test_priceDifferenceChecker_uniswapCheckPriceDifference_shouldReturnTrue_rateUp()
        external
    {
        // up
        (, , , , uint256 lastCheckPriceBefore, ) = vault
            .uniswapGetLocalPriceDifferenceCheckerStorage(
                priceDifferentCheckerStoragePointerRateUp
            );

        _rateUp();

        vm.prank(address(vault));
        assertTrue(
            vault.uniswapCheckPriceDifference(
                priceDifferentCheckerStoragePointerRateUp
            )
        );

        uint256 currentRate = reg.dittoOracle.consult(
            usdcAddress,
            1e6,
            wethAddress,
            poolFee,
            address(reg.uniswapFactory)
        );
        (, , , , uint256 lastCheckPriceAfter, ) = vault
            .uniswapGetLocalPriceDifferenceCheckerStorage(
                priceDifferentCheckerStoragePointerRateUp
            );

        assertGt(lastCheckPriceAfter, lastCheckPriceBefore);
        assertEq(lastCheckPriceAfter, currentRate);
    }

    function test_priceDifferenceChecker_uniswapCheckPriceDifference_shouldReturnTrue_rateDown()
        external
    {
        // down
        (, , , , uint256 lastCheckPriceBefore, ) = vault
            .uniswapGetLocalPriceDifferenceCheckerStorage(
                priceDifferentCheckerStoragePointerRateDown
            );

        _rateDown();

        vm.prank(address(vault));
        assertTrue(
            vault.uniswapCheckPriceDifference(
                priceDifferentCheckerStoragePointerRateDown
            )
        );

        uint256 currentRate = reg.dittoOracle.consult(
            usdcAddress,
            1e6,
            wethAddress,
            poolFee,
            address(reg.uniswapFactory)
        );
        (, , , , uint256 lastCheckPriceAfter, ) = vault
            .uniswapGetLocalPriceDifferenceCheckerStorage(
                priceDifferentCheckerStoragePointerRateDown
            );

        assertLt(lastCheckPriceAfter, lastCheckPriceBefore);
        assertEq(lastCheckPriceAfter, currentRate);
    }

    function test_priceDifferenceChecker_uniswapCheckPriceDifference_accessControl()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.uniswapCheckPriceDifference(
            priceDifferentCheckerStoragePointerRateDown
        );

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.uniswapCheckPriceDifference(
            priceDifferentCheckerStoragePointerRateDown
        );

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.uniswapCheckPriceDifference(
            priceDifferentCheckerStoragePointerRateUp
        );
    }

    function test_priceDifferenceChecker_uniswapCheckPriceDifferenceView_shouldReturnFalse()
        external
    {
        assertFalse(
            vault.uniswapCheckPriceDifferenceView(
                priceDifferentCheckerStoragePointerRateUp
            )
        );
    }

    function test_priceDifferenceChecker_uniswapCheckPriceDifferenceView_shouldReturnTrue_rateUp()
        external
    {
        _rateUp();

        assertTrue(
            vault.uniswapCheckPriceDifferenceView(
                priceDifferentCheckerStoragePointerRateUp
            )
        );
    }

    function test_priceDifferenceChecker_uniswapCheckPriceDifferenceView_shouldReturnTrue_rateDown()
        external
    {
        _rateDown();

        assertTrue(
            vault.uniswapCheckPriceDifferenceView(
                priceDifferentCheckerStoragePointerRateDown
            )
        );
    }

    function test_priceDifferenceChecker_uniswapChangeTokensAndFeePriceDiffChecker()
        external
    {
        vm.prank(vaultOwner);
        vault.uniswapChangeTokensAndFeePriceDiffChecker(
            pool2,
            priceDifferentCheckerStoragePointerRateUp
        );

        (address token0, address token1, uint24 fee, , , ) = vault
            .uniswapGetLocalPriceDifferenceCheckerStorage(
                priceDifferentCheckerStoragePointerRateUp
            );

        assertEq(token0, pool2.token0());
        assertEq(token1, pool2.token1());
        assertEq(fee, pool2.fee());
    }

    function test_priceDifferenceChecker_uniswapChangeTokensAndFeePriceDiffChecker_accessControl()
        external
    {
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.uniswapChangeTokensAndFeePriceDiffChecker(
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
        vault.uniswapChangeTokensAndFeePriceDiffChecker(
            pool2,
            priceDifferentCheckerStoragePointerRateUp
        );
    }

    function test_priceDifferenceChecker_uniswapChangePercentageDeviationE3()
        external
    {
        vm.prank(vaultOwner);
        vault.uniswapChangePercentageDeviationE3(
            1010,
            priceDifferentCheckerStoragePointerRateUp
        );

        (, , , uint24 percentageDeviation_E3, , ) = vault
            .uniswapGetLocalPriceDifferenceCheckerStorage(
                priceDifferentCheckerStoragePointerRateUp
            );

        assertEq(percentageDeviation_E3, 1010);
    }

    function test_priceDifferenceChecker_uniswapChangePercentageDeviationE3_shouldRevertInvalidPercentage()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            IPriceDifferenceCheckerLogicBase
                .PriceDifferenceChecker_InvalidPercentageDeviation
                .selector
        );
        vault.uniswapChangePercentageDeviationE3(
            2001,
            priceDifferentCheckerStoragePointerRateUp
        );
    }

    function test_priceDifferenceChecker_uniswapChangePercentageDeviationE3_accessControl()
        external
    {
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.uniswapChangePercentageDeviationE3(
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
        vault.uniswapChangePercentageDeviationE3(
            1000,
            priceDifferentCheckerStoragePointerRateUp
        );
    }

    // --------------------

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
                    amountIn: 25 * 1e18,
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
}
