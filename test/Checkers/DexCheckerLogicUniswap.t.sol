// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IV3SwapRouter} from "../../src/vault/interfaces/external/IV3SwapRouter.sol";

import {IDexCheckerLogicBase} from "../../src/vault/logics/Checkers/DexCheckerLogicBase.sol";
import {DexCheckerLogicUniswap} from "../../src/vault/logics/Checkers/DexCheckerLogicUniswap.sol";
import {AccessControlLogic} from "../../src/vault/logics/AccessControlLogic.sol";
import {BaseContract} from "../../src/vault/libraries/BaseContract.sol";
import {VaultFactory} from "../../src/VaultFactory.sol";
import {TransferHelper} from "../../src/vault/libraries/utils/TransferHelper.sol";
import {IVaultLogic} from "../../src/vault/interfaces/IVaultLogic.sol";

import {IUniswapLogic} from "../../src/vault/interfaces/ourLogic/dexAutomation/IUniswapLogic.sol";

import {FullDeploy, Registry, VaultProxyAdmin} from "../../script/FullDeploy.s.sol";

contract DexCheckerLogicUniswapTest is Test, FullDeploy {
    bool isTest = true;

    Registry.Contracts reg;

    DexCheckerLogicUniswap vault;
    address vaultOwner = makeAddr("VAULT_OWNER");
    address executor = makeAddr("EXECUTOR");

    IUniswapV3Pool pool =
        IUniswapV3Pool(0x88f3C15523544835fF6c738DDb30995339AD57d6);
    uint24 poolFee;

    // mainnet USDC
    address usdcAddress = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    // mainnet WMATIC
    address wmaticAddress = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

    address donor = 0xA374094527e1673A86dE625aa59517c5dE346d32; // wallet for token airdrop

    uint256 nftIdOutOfRange;
    uint256 nftId;

    function setUp() public {
        vm.createSelectFork(vm.envString("POL_RPC_URL"));
        poolFee = pool.fee();

        vm.startPrank(donor);
        TransferHelper.safeTransfer(usdcAddress, address(vaultOwner), 3000e6);
        TransferHelper.safeTransfer(
            wmaticAddress,
            address(vaultOwner),
            3000e18
        );
        vm.stopPrank();

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

        vm.startPrank(vaultOwner);
        vault = DexCheckerLogicUniswap(vaultFactory.deploy(1, 1));

        TransferHelper.safeApprove(
            usdcAddress,
            address(vault),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            wmaticAddress,
            address(vault),
            type(uint256).max
        );
        vm.stopPrank();

        (, int24 currentTick, , , , , ) = pool.slot0();
        int24 minTick = ((currentTick + 120) / 60) * 60;
        int24 maxTick = ((currentTick + 4000) / 60) * 60;

        vm.startPrank(address(vault));
        IVaultLogic(address(vault)).depositERC20(
            wmaticAddress,
            1000e18,
            vaultOwner
        );

        // mint new nft for tests
        nftIdOutOfRange = IUniswapLogic(address(vault)).uniswapMintNft(
            pool,
            minTick,
            maxTick,
            1000e18,
            0,
            false,
            true,
            1e18
        );

        // in range
        minTick = ((currentTick - 4000) / 60) * 60;

        uint160 sqrtPriceX96 = reg.lens.dexLogicLens.getCurrentSqrtRatioX96(
            pool
        );

        uint256 RTarget = reg.lens.dexLogicLens.getTargetRE18ForTickRange(
            minTick,
            maxTick,
            pool
        );

        uint256 usdcAmount = reg.lens.dexLogicLens.token1AmountForTargetRE18(
            sqrtPriceX96,
            1000e18,
            1000e6,
            RTarget,
            poolFee
        );

        uint256 wmaticAmount = reg.lens.dexLogicLens.token0AmountForTargetRE18(
            sqrtPriceX96,
            usdcAmount,
            RTarget
        );

        IVaultLogic(address(vault)).depositERC20(
            wmaticAddress,
            wmaticAmount,
            vaultOwner
        );
        IVaultLogic(address(vault)).depositERC20(
            usdcAddress,
            usdcAmount,
            vaultOwner
        );

        // mint new nft for tests
        nftId = IUniswapLogic(address(vault)).uniswapMintNft(
            pool,
            minTick,
            maxTick,
            wmaticAmount,
            usdcAmount,
            false,
            true,
            1e18
        );

        vault.uniswapDexCheckerInitialize(nftId, keccak256("inTickRange"));
        vault.uniswapDexCheckerInitialize(
            nftIdOutOfRange,
            keccak256("outOfTickRange")
        );

        vm.stopPrank();
    }

    function test_dexCheckerUniswap_shouldReturnCorrectLocalState() external {
        uint256 _nftId = vault.uniswapGetLocalDexCheckerStorage(
            keccak256("inTickRange")
        );
        assertEq(_nftId, nftId);
        _nftId = vault.uniswapGetLocalDexCheckerStorage(
            keccak256("outOfTickRange")
        );
        assertEq(_nftId, nftIdOutOfRange);
    }

    function test_dexCheckerUniswap_cannotBeInitalizedMultipleTimes() external {
        vm.prank(address(vault));
        vm.expectRevert(
            IDexCheckerLogicBase.DexChecker_AlreadyInitialized.selector
        );
        vault.uniswapDexCheckerInitialize(nftId, keccak256("inTickRange"));
    }

    function test_dexCheckerUniswap_shouldRevertIfNotInitialized() external {
        bytes32 storagePointer = keccak256("not initialized");

        vm.expectRevert(
            IDexCheckerLogicBase.DexChecker_NotInitialized.selector
        );
        vault.uniswapCheckOutOfTickRange(storagePointer);

        vm.expectRevert(
            IDexCheckerLogicBase.DexChecker_NotInitialized.selector
        );
        vault.uniswapCheckFeesExistence(storagePointer);
    }

    function test_dexCheckerUniswap_uniswapCheckOutOfTickRange_shouldReturnFalse()
        external
    {
        assertFalse(vault.uniswapCheckOutOfTickRange(keccak256("inTickRange")));
    }

    function test_dexCheckerUniswap_uniswapCheckOutOfTickRange_shouldReturnTrue()
        external
    {
        assertTrue(
            vault.uniswapCheckOutOfTickRange(keccak256("outOfTickRange"))
        );
    }

    function test_dexCheckerUniswap_uniswapCheckInTickRange_shouldReturnFalse()
        external
    {
        assertFalse(vault.uniswapCheckInTickRange(keccak256("outOfTickRange")));
    }

    function test_dexCheckerUniswap_uniswapCheckInTickRange_shouldReturnTrue()
        external
    {
        assertTrue(vault.uniswapCheckInTickRange(keccak256("inTickRange")));
    }

    function test_dexCheckerUniswap_uniswapCheckFeesExistence_shouldReturnFalse()
        external
    {
        assertFalse(vault.uniswapCheckFeesExistence(keccak256("inTickRange")));
    }

    function test_dexCheckerUniswap_uniswapCheckFeesExistence_shouldReturnTrue()
        external
    {
        _swaps();
        assertTrue(vault.uniswapCheckFeesExistence(keccak256("inTickRange")));
    }

    // --------------------

    function _swaps() internal {
        vm.startPrank(donor);
        TransferHelper.safeApprove(
            wmaticAddress,
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
                    tokenIn: wmaticAddress,
                    tokenOut: usdcAddress,
                    fee: poolFee,
                    recipient: donor,
                    amountIn: 500e18,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        }
        vm.stopPrank();
    }
}
