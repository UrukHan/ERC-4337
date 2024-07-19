// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IV3SwapRouter} from "../../src/vault/interfaces/external/IV3SwapRouter.sol";

import {IDexCheckerLogicBase} from "../../src/vault/logics/Checkers/DexCheckerLogicBase.sol";
import {DexCheckerLogicPancakeswap} from "../../src/vault/logics/Checkers/DexCheckerLogicPancakeswap.sol";
import {AccessControlLogic} from "../../src/vault/logics/AccessControlLogic.sol";
import {BaseContract} from "../../src/vault/libraries/BaseContract.sol";
import {VaultFactory} from "../../src/VaultFactory.sol";
import {TransferHelper} from "../../src/vault/libraries/utils/TransferHelper.sol";
import {IVaultLogic} from "../../src/vault/interfaces/IVaultLogic.sol";

import {IPancakeswapLogic} from "../../src/vault/interfaces/ourLogic/dexAutomation/IPancakeswapLogic.sol";

import {FullDeploy, Registry, VaultProxyAdmin} from "../../script/FullDeploy.s.sol";

contract DexCheckerLogicPancakeswapTest is Test, FullDeploy {
    bool isTest = true;

    Registry.Contracts reg;

    DexCheckerLogicPancakeswap vault;
    address vaultOwner = makeAddr("VAULT_OWNER");
    address executor = makeAddr("EXECUTOR");

    IUniswapV3Pool pool =
        IUniswapV3Pool(0x133B3D95bAD5405d14d53473671200e9342896BF);
    uint24 poolFee;

    address cakeAddress = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82; // mainnet CAKE
    address wbnbAddress = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; // mainnet WBNB
    address donor = 0x8894E0a0c962CB723c1976a4421c95949bE2D4E3; // wallet for token airdrop

    uint256 nftIdOutOfRange;
    uint256 nftId;

    function setUp() public {
        vm.createSelectFork(vm.envString("BNB_RPC_URL"));
        poolFee = pool.fee();

        vm.startPrank(donor);
        TransferHelper.safeTransfer(cakeAddress, address(vaultOwner), 3000e18);
        TransferHelper.safeTransfer(wbnbAddress, address(vaultOwner), 20e18);
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
        vault = DexCheckerLogicPancakeswap(vaultFactory.deploy(1, 1));

        TransferHelper.safeApprove(
            wbnbAddress,
            address(vault),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            cakeAddress,
            address(vault),
            type(uint256).max
        );
        vm.stopPrank();

        (, bytes memory data) = address(pool).staticcall(
            // 0x3850c7bd - selector of "slot0()"
            abi.encodeWithSelector(0x3850c7bd)
        );
        (, int24 currentTick, , , , , ) = abi.decode(
            data,
            (uint160, int24, int16, int16, int16, uint256, bool)
        );
        int24 minTick = ((currentTick + 120) / 50) * 50;
        int24 maxTick = ((currentTick + 4000) / 50) * 50;

        vm.startPrank(address(vault));
        IVaultLogic(address(vault)).depositERC20(
            cakeAddress,
            1000e18,
            vaultOwner
        );

        // mint new nft for tests
        nftIdOutOfRange = IPancakeswapLogic(address(vault)).pancakeswapMintNft(
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
        minTick = ((currentTick - 4000) / 50) * 50;

        uint160 sqrtPriceX96 = reg.lens.dexLogicLens.getCurrentSqrtRatioX96(
            pool
        );

        uint256 RTarget = reg.lens.dexLogicLens.getTargetRE18ForTickRange(
            minTick,
            maxTick,
            pool
        );

        uint256 wbnbAmount = reg.lens.dexLogicLens.token1AmountForTargetRE18(
            sqrtPriceX96,
            1000e18,
            2e18,
            RTarget,
            poolFee
        );

        uint256 cakeAmount = reg.lens.dexLogicLens.token0AmountForTargetRE18(
            sqrtPriceX96,
            wbnbAmount,
            RTarget
        );

        IVaultLogic(address(vault)).depositERC20(
            wbnbAddress,
            wbnbAmount,
            vaultOwner
        );
        IVaultLogic(address(vault)).depositERC20(
            cakeAddress,
            cakeAmount,
            vaultOwner
        );

        // mint new nft for tests
        nftId = IPancakeswapLogic(address(vault)).pancakeswapMintNft(
            pool,
            minTick,
            maxTick,
            cakeAmount,
            wbnbAmount,
            false,
            true,
            1e18
        );

        vault.pancakeswapDexCheckerInitialize(nftId, keccak256("inTickRange"));
        vault.pancakeswapDexCheckerInitialize(
            nftIdOutOfRange,
            keccak256("outOfTickRange")
        );

        vm.stopPrank();
    }

    function test_dexCheckerPancakeswap_shouldReturnCorrectLocalState()
        external
    {
        uint256 _nftId = vault.pancakeswapGetLocalDexCheckerStorage(
            keccak256("inTickRange")
        );
        assertEq(_nftId, nftId);
        _nftId = vault.pancakeswapGetLocalDexCheckerStorage(
            keccak256("outOfTickRange")
        );
        assertEq(_nftId, nftIdOutOfRange);
    }

    function test_dexCheckerPancakeswap_cannotBeInitalizedMultipleTimes()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert(
            IDexCheckerLogicBase.DexChecker_AlreadyInitialized.selector
        );
        vault.pancakeswapDexCheckerInitialize(nftId, keccak256("inTickRange"));
    }

    function test_dexCheckerPancakeswap_shouldRevertIfNotInitialized()
        external
    {
        bytes32 storagePointer = keccak256("not initialized");

        vm.expectRevert(
            IDexCheckerLogicBase.DexChecker_NotInitialized.selector
        );
        vault.pancakeswapCheckOutOfTickRange(storagePointer);

        vm.expectRevert(
            IDexCheckerLogicBase.DexChecker_NotInitialized.selector
        );
        vault.pancakeswapCheckFeesExistence(storagePointer);
    }

    function test_dexCheckerPancakeswap_pancakeswapCheckOutOfTickRange_shouldReturnFalse()
        external
    {
        assertFalse(
            vault.pancakeswapCheckOutOfTickRange(keccak256("inTickRange"))
        );
    }

    function test_dexCheckerPancakeswap_pancakeswapCheckOutOfTickRange_shouldReturnTrue()
        external
    {
        assertTrue(
            vault.pancakeswapCheckOutOfTickRange(keccak256("outOfTickRange"))
        );
    }

    function test_dexCheckerPancakeswap_pancakeswapCheckInTickRange_shouldReturnFalse()
        external
    {
        assertFalse(
            vault.pancakeswapCheckInTickRange(keccak256("outOfTickRange"))
        );
    }

    function test_dexCheckerPancakeswap_pancakeswapCheckInTickRange_shouldReturnTrue()
        external
    {
        assertTrue(vault.pancakeswapCheckInTickRange(keccak256("inTickRange")));
    }

    function test_dexCheckerPancakeswap_pancakeswapCheckFeesExistence_shouldReturnFalse()
        external
    {
        assertFalse(
            vault.pancakeswapCheckFeesExistence(keccak256("inTickRange"))
        );
    }

    function test_dexCheckerPancakeswap_pancakeswapCheckFeesExistence_shouldReturnTrue()
        external
    {
        _swaps();
        assertTrue(
            vault.pancakeswapCheckFeesExistence(keccak256("inTickRange"))
        );
    }

    // --------------------

    function _swaps() internal {
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
                    amountIn: 2e18,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        }
        vm.stopPrank();
    }
}
