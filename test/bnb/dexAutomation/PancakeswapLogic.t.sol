// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import {IV3SwapRouter} from "../../../src/vault/interfaces/external/IV3SwapRouter.sol";
import {VaultFactory} from "../../../src/VaultFactory.sol";
import {IDexBaseLogic} from "../../../src/vault/interfaces/ourLogic/dexAutomation/IDexBaseLogic.sol";
import {PancakeswapLogic} from "../../../src/vault/logics/OurLogic/dexAutomation/PancakeswapLogic.sol";
import {TransferHelper} from "../../../src/vault/libraries/utils/TransferHelper.sol";
import {DexLogicLib} from "../../../src/vault/libraries/DexLogicLib.sol";
import {AccessControlLogic} from "../../../src/vault/logics/AccessControlLogic.sol";
import {VaultLogic} from "../../../src/vault/logics/VaultLogic.sol";
import {BaseContract, Constants} from "../../../src/vault/libraries/BaseContract.sol";
import {DexLogicLens} from "../../../src/lens/DexLogicLens.sol";

import {FullDeploy, Registry, VaultProxyAdmin} from "../../../script/FullDeploy.s.sol";

contract PancakeswapLogicTest is Test, FullDeploy {
    bool isTest = true;

    PancakeswapLogic vault;
    Registry.Contracts reg;

    IUniswapV3Pool pool =
        IUniswapV3Pool(0x133B3D95bAD5405d14d53473671200e9342896BF);
    uint24 poolFee;

    address cakeAddress = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82; // mainnet CAKE
    address wbnbAddress = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; // mainnet WBNB
    address donor = 0x8894E0a0c962CB723c1976a4421c95949bE2D4E3; // wallet for token airdrop

    address vaultOwner = makeAddr("VAULT_OWNER");
    address executor = makeAddr("EXECUTOR");
    address user = makeAddr("USER");

    uint256 nftId;

    function setUp() public {
        vm.createSelectFork(vm.envString("BNB_RPC_URL"));

        poolFee = pool.fee();

        reg = Registry.contractsByChainId(block.chainid);

        vm.startPrank(donor);
        IERC20(cakeAddress).transfer(vaultOwner, 20000e18);
        IERC20(wbnbAddress).transfer(vaultOwner, 10e18);
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
        vault = PancakeswapLogic(vaultFactory.deploy(1, 1));

        IERC20(wbnbAddress).approve(address(vault), type(uint256).max);
        IERC20(cakeAddress).approve(address(vault), type(uint256).max);

        (, bytes memory data) = address(pool).staticcall(
            // 0x3850c7bd - selector of "slot0()"
            abi.encodeWithSelector(0x3850c7bd)
        );
        (, int24 currentTick, , , , , ) = abi.decode(
            data,
            (uint160, int24, int16, int16, int16, uint256, bool)
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
            500e18,
            1e18,
            RTarget,
            poolFee
        );

        uint256 cakeAmount = reg.lens.dexLogicLens.token0AmountForTargetRE18(
            sqrtPriceX96,
            wbnbAmount,
            RTarget
        );

        TransferHelper.safeApprove(
            wbnbAddress,
            address(reg.pancakeswapNFTPositionManager),
            wbnbAmount
        );
        TransferHelper.safeApprove(
            cakeAddress,
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
            address(vault),
            nftId
        );

        AccessControlLogic(address(vault)).grantRole(
            Constants.EXECUTOR_ROLE,
            address(executor)
        );
        vm.stopPrank();
    }

    // =========================
    // pancakeswapChangeTickRange
    // =========================

    function test_bnb_pancakeswapLogic_pancakeswapChangeTickRange_accessControl()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.pancakeswapChangeTickRange(0, 0, nftId, 0.005e18);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.pancakeswapChangeTickRange(0, 0, nftId, 0.005e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                address(this)
            )
        );
        vault.pancakeswapChangeTickRange(0, 0, nftId, 0.005e18);
    }

    function test_bnb_pancakeswapLogic_pancakeswapChangeTickRange_shouldSwapTicks()
        external
    {
        vm.prank(address(vault));
        uint256 newNftId = vault.pancakeswapChangeTickRange(
            100,
            -100,
            nftId,
            0.005e18
        );

        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = reg
            .pancakeswapNFTPositionManager
            .positions(newNftId);

        assertEq(tickLower, -100);
        assertEq(tickUpper, 100);
    }

    function test_bnb_pancakeswapLogic_pancakeswapChangeTickRange_shouldNotMintNewNftIfTicksAreSame()
        external
    {
        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = reg
            .pancakeswapNFTPositionManager
            .positions(nftId);

        vm.prank(address(vault));
        uint256 newNftId = vault.pancakeswapChangeTickRange(
            tickLower,
            tickUpper,
            nftId,
            0.005e18
        );

        assertEq(newNftId, nftId);

        vm.prank(address(vault));
        newNftId = vault.pancakeswapChangeTickRange(
            tickUpper,
            tickLower,
            nftId,
            0.005e18
        );

        assertEq(newNftId, nftId);
    }

    function test_bnb_pancakeswapLogic_pancakeswapChangeTickRange_shouldSuccessfulChangeTicks()
        external
    {
        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = reg
            .pancakeswapNFTPositionManager
            .positions(nftId);

        vm.prank(address(vault));
        uint256 newNftId = vault.pancakeswapChangeTickRange(
            tickLower - 100,
            tickUpper + 100,
            nftId,
            0.005e18
        );

        (, , , , , int24 newTickLower, int24 newTickUpper, , , , , ) = reg
            .pancakeswapNFTPositionManager
            .positions(newNftId);

        assertEq(newTickLower, tickLower - 100);
        assertEq(newTickUpper, tickUpper + 100);
    }

    function test_bnb_pancakeswapLogic_pancakeswapChangeTickRange_failedMEVCheck()
        external
    {
        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = reg
            .pancakeswapNFTPositionManager
            .positions(nftId);

        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.pancakeswapChangeTickRange(
            tickLower - 120,
            tickUpper + 120,
            nftId,
            0
        );
    }

    // =========================
    // pancakeswapMintNft
    // =========================

    function test_bnb_pancakeswapLogic_pancakeswapMintNft_accessControl()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.pancakeswapMintNft(pool, 100, 200, 0, 0, false, false, 0);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.pancakeswapMintNft(pool, 100, 200, 0, 0, false, false, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                address(this)
            )
        );
        vault.pancakeswapMintNft(pool, 100, 200, 0, 0, false, false, 0);
    }

    function test_bnb_pancakeswapLogic_pancakeswapMintNft_shouldSuccessfulMintNewNft_woFlagSwapFlag()
        external
    {
        (, bytes memory data) = address(pool).staticcall(
            // 0x3850c7bd - selector of "slot0()"
            abi.encodeWithSelector(0x3850c7bd)
        );
        (, int24 currentTick, , , , , ) = abi.decode(
            data,
            (uint160, int24, int24, uint256, uint256, uint128, uint128)
        );

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            cakeAddress,
            500e18,
            vaultOwner
        );
        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(wbnbAddress, 1e18, vaultOwner);

        vm.prank(address(vault));
        uint256 newNftId = vault.pancakeswapMintNft(
            pool,
            ((currentTick - 4000) / 50) * 50,
            ((currentTick + 4000) / 50) * 50,
            500e18,
            1e18,
            false,
            false,
            0.005e18
        );

        (uint256 amount0, uint256 amount1) = reg.lens.dexLogicLens.principal(
            newNftId,
            reg.pancakeswapNFTPositionManager,
            reg.pancakeswapFactory
        );

        assertGt(amount0, 0);
        assertGt(amount1, 0);
    }

    function test_bnb_pancakeswapLogic_pancakeswapMintNft_shouldSuccessfulMintNewNft_swapFlag()
        external
    {
        (, bytes memory data) = address(pool).staticcall(
            // 0x3850c7bd - selector of "slot0()"
            abi.encodeWithSelector(0x3850c7bd)
        );
        (, int24 currentTick, , , , , ) = abi.decode(
            data,
            (uint160, int24, int24, uint256, uint256, uint128, uint128)
        );

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            cakeAddress,
            500e18,
            vaultOwner
        );
        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(wbnbAddress, 1e18, vaultOwner);

        vm.prank(address(vault));
        uint256 newNftId = vault.pancakeswapMintNft(
            pool,
            ((currentTick - 4000) / 50) * 50,
            ((currentTick + 4000) / 50) * 50,
            500e18,
            1e18,
            false,
            true,
            0.005e18
        );

        (uint256 amount0, uint256 amount1) = reg.lens.dexLogicLens.principal(
            newNftId,
            reg.pancakeswapNFTPositionManager,
            reg.pancakeswapFactory
        );

        assertGt(amount0, 0);
        assertGt(amount1, 0);
    }

    function test_bnb_pancakeswapLogic_pancakeswapMintNft_shouldSuccessfulMintNewNft_shouldUseFullBalancesOfTokensFromVault()
        external
    {
        (, bytes memory data) = address(pool).staticcall(
            // 0x3850c7bd - selector of "slot0()"
            abi.encodeWithSelector(0x3850c7bd)
        );
        (, int24 currentTick, , , , , ) = abi.decode(
            data,
            (uint160, int24, int24, uint256, uint256, uint128, uint128)
        );

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            cakeAddress,
            500e18,
            vaultOwner
        );
        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(wbnbAddress, 1e18, vaultOwner);

        vm.prank(address(vault));
        uint256 newNftId = vault.pancakeswapMintNft(
            pool,
            ((currentTick - 4000) / 50) * 50,
            ((currentTick + 4000) / 50) * 50,
            0,
            0,
            true,
            true,
            0.005e18
        );

        (uint256 amount0, uint256 amount1) = reg.lens.dexLogicLens.principal(
            newNftId,
            reg.pancakeswapNFTPositionManager,
            reg.pancakeswapFactory
        );

        assertGt(amount0, 0);
        assertGt(amount1, 0);
    }

    function test_bnb_pancakeswapLogic_pancakeswapMintNft_addZeroError()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert(
            DexLogicLib.DexLogicLib_ZeroNumberOfTokensCannotBeAdded.selector
        );
        vault.pancakeswapMintNft(pool, 100, 200, 0, 0, false, false, 1e18);
    }

    function test_bnb_pancakeswapLogic_pancakeswapMintNft_shouldSwapTicksIfMinGtMax()
        external
    {
        (, bytes memory data) = address(pool).staticcall(
            // 0x3850c7bd - selector of "slot0()"
            abi.encodeWithSelector(0x3850c7bd)
        );
        (, int24 currentTick, , , , , ) = abi.decode(
            data,
            (uint160, int24, int24, uint256, uint256, uint128, uint128)
        );

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            cakeAddress,
            500e18,
            vaultOwner
        );
        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(wbnbAddress, 1e18, vaultOwner);

        vm.prank(address(vault));
        uint256 newNftId = vault.pancakeswapMintNft(
            pool,
            ((currentTick + 4000) / 50) * 50,
            ((currentTick - 4000) / 50) * 50,
            500e18,
            1e18,
            false,
            true,
            0.005e18
        );

        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = reg
            .pancakeswapNFTPositionManager
            .positions(newNftId);

        assertEq(tickLower, ((currentTick - 4000) / 50) * 50);
        assertEq(tickUpper, ((currentTick + 4000) / 50) * 50);
    }

    function test_bnb_pancakeswapLogic_pancakeswapMintNft_failedMEVCheck()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.pancakeswapMintNft(pool, 100, 200, 0, 0, false, false, 0);
    }

    // =========================
    // pancakeswapAddLiquidity
    // =========================

    function test_bnb_pancakeswapLogic_pancakeswapAddLiquidity_accessControl()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.pancakeswapAddLiquidity(nftId, 0, 0, false, false, 0.005e18);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.pancakeswapAddLiquidity(nftId, 0, 0, false, false, 0.005e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                address(this)
            )
        );
        vault.pancakeswapAddLiquidity(nftId, 0, 0, false, false, 0.005e18);
    }

    function test_bnb_pancakeswapLogic_pancakeswapAddLiquidity_shouldRevertIfNftDoesNotExists()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert("Invalid token ID");
        vault.pancakeswapAddLiquidity(
            type(uint128).max,
            0,
            0,
            false,
            false,
            0.005e18
        );
    }

    function test_bnb_pancakeswapLogic_pancakeswapAddLiquidity_shouldSuccessfulpancakeswapAddLiquidity_woSwapFlag()
        external
    {
        (uint256 amount0Before, uint256 amount1Before) = reg
            .lens
            .dexLogicLens
            .tvl(
                nftId,
                reg.pancakeswapNFTPositionManager,
                reg.pancakeswapFactory
            );

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            cakeAddress,
            500e18,
            vaultOwner
        );
        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(wbnbAddress, 1e18, vaultOwner);

        vm.prank(address(vault));
        vault.pancakeswapAddLiquidity(
            nftId,
            500e18,
            1e18,
            false,
            false,
            0.005e18
        );

        (uint256 amount0After, uint256 amount1After) = reg
            .lens
            .dexLogicLens
            .tvl(
                nftId,
                reg.pancakeswapNFTPositionManager,
                reg.pancakeswapFactory
            );

        assertGe(amount0After, amount0Before);
        assertGe(amount1After, amount1Before);
    }

    function test_bnb_pancakeswapLogic_pancakeswapAddLiquidity_shouldSuccessfulpancakeswapAddLiquidity_swapFlag()
        external
    {
        (uint256 amount0Before, uint256 amount1Before) = reg
            .lens
            .dexLogicLens
            .tvl(
                nftId,
                reg.pancakeswapNFTPositionManager,
                reg.pancakeswapFactory
            );

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            cakeAddress,
            500e18,
            vaultOwner
        );
        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(wbnbAddress, 1e18, vaultOwner);

        vm.prank(address(vault));
        vault.pancakeswapAddLiquidity(
            nftId,
            500e18,
            1e18,
            false,
            true,
            0.005e18
        );

        (uint256 amount0After, uint256 amount1After) = reg
            .lens
            .dexLogicLens
            .tvl(
                nftId,
                reg.pancakeswapNFTPositionManager,
                reg.pancakeswapFactory
            );

        assertGe(amount0After, amount0Before);
        assertGe(amount1After, amount1Before);
    }

    function test_bnb_pancakeswapLogic_pancakeswapAddLiquidity_failedMEVCheck()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.pancakeswapAddLiquidity(nftId, 500e18, 1e18, false, false, 0);
    }

    function test_bnb_pancakeswapLogic_pancakeswapAddLiquidity_shouldUseFullBalancesOfTokensFromVault()
        external
    {
        (uint256 amount0Before, uint256 amount1Before) = reg
            .lens
            .dexLogicLens
            .tvl(
                nftId,
                reg.pancakeswapNFTPositionManager,
                reg.pancakeswapFactory
            );

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            cakeAddress,
            500e18,
            vaultOwner
        );
        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(wbnbAddress, 1e18, vaultOwner);

        vm.prank(address(vault));
        vault.pancakeswapAddLiquidity(nftId, 0, 0, true, true, 0.005e18);

        (uint256 amount0After, uint256 amount1After) = reg
            .lens
            .dexLogicLens
            .tvl(
                nftId,
                reg.pancakeswapNFTPositionManager,
                reg.pancakeswapFactory
            );

        assertGe(amount0After, amount0Before);
        assertGe(amount1After, amount1Before);
    }

    // =========================
    // pancakeswapAutoCompound
    // =========================

    function test_bnb_pancakeswapLogic_pancakeswapAutoCompound_accessControl()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.pancakeswapAutoCompound(nftId, 0.005e18);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.pancakeswapAutoCompound(nftId, 0.005e18);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.pancakeswapAutoCompound(nftId, 0.005e18);
    }

    function test_bnb_pancakeswapLogic_pancakeswapAutoCompound_shouldRevertWithNftWhichNotExists()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert("Invalid token ID");
        vault.pancakeswapAutoCompound(type(uint128).max, 0.005e18);
    }

    function test_bnb_pancakeswapLogic_pancakeswapAutoCompound_failedMEVCheck()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.pancakeswapAutoCompound(nftId, 0);
    }

    function test_bnb_pancakeswapLogic_pancakeswapAutoCompound_shouldDoNothingIfNoFeesInNft()
        external
    {
        vm.prank(address(vault));
        vault.pancakeswapCollectFees(nftId);

        (uint256 amount0Before, uint256 amount1Before) = reg
            .lens
            .dexLogicLens
            .principal(
                nftId,
                reg.pancakeswapNFTPositionManager,
                reg.pancakeswapFactory
            );

        vm.prank(address(vault));
        vault.pancakeswapAutoCompound(nftId, 0.005e18);

        (uint256 amount0After, uint256 amount1After) = reg
            .lens
            .dexLogicLens
            .principal(
                nftId,
                reg.pancakeswapNFTPositionManager,
                reg.pancakeswapFactory
            );

        assertEq(amount0Before, amount0After);
        assertEq(amount1Before, amount1After);
    }

    function test_bnb_pancakeswapLogic_pancakeswapAutoCompound_shouldSuccessfulpancakeswapAutoCompoundTwice()
        external
    {
        // do 8 swaps
        _makeUniSwaps(4);

        (uint256 fees0Before, uint256 fees1Before) = reg.lens.dexLogicLens.fees(
            nftId,
            reg.pancakeswapNFTPositionManager,
            reg.pancakeswapFactory
        );

        assertNotEq(0, fees0Before);
        assertNotEq(0, fees1Before);

        vm.prank(address(vault));
        vault.pancakeswapAutoCompound(nftId, 0.005e18);

        (uint256 fees0After, uint256 fees1After) = reg.lens.dexLogicLens.fees(
            nftId,
            reg.pancakeswapNFTPositionManager,
            reg.pancakeswapFactory
        );

        assertApproxEqAbs(0, fees0After, 1e18);
        assertApproxEqAbs(0, fees1After, 1e18);

        // do 8 swaps
        _makeUniSwaps(4);

        (fees0Before, fees1Before) = reg.lens.dexLogicLens.fees(
            nftId,
            reg.pancakeswapNFTPositionManager,
            reg.pancakeswapFactory
        );
        assertNotEq(0, fees0Before);
        assertNotEq(0, fees1Before);

        vm.prank(address(vault));
        vault.pancakeswapAutoCompound(nftId, 0.005e18);

        (fees0After, fees1After) = reg.lens.dexLogicLens.fees(
            nftId,
            reg.pancakeswapNFTPositionManager,
            reg.pancakeswapFactory
        );

        assertApproxEqAbs(0, fees0After, 1e18);
        assertApproxEqAbs(0, fees1After, 1e18);
    }

    // =========================
    // pancakeswapSwapExactInput
    // =========================

    function test_bnb_pancakeswapLogic_pancakeswapSwapExactInput_accessControl()
        external
    {
        address[] memory tokens = new address[](2);
        uint24[] memory poolFees = new uint24[](1);

        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.pancakeswapSwapExactInput(tokens, poolFees, 0, false, false, 0);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.pancakeswapSwapExactInput(tokens, poolFees, 0, false, false, 0);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.pancakeswapSwapExactInput(tokens, poolFees, 0, false, false, 0);
    }

    function test_bnb_pancakeswapLogic_pancakeswapSwapExactInput_shouldRevertIfTokensNotEnough()
        external
    {
        address[] memory tokens = new address[](2);
        uint24[] memory poolFees = new uint24[](1);

        tokens[0] = wbnbAddress;
        tokens[1] = cakeAddress;
        poolFees[0] = poolFee;

        vm.prank(address(vault));
        vm.expectRevert(
            DexLogicLib.DexLogicLib_NotEnoughTokenBalances.selector
        );
        vault.pancakeswapSwapExactInput(
            tokens,
            poolFees,
            1e18,
            false,
            false,
            0.005e18
        );
    }

    function test_bnb_pancakeswapLogic_pancakeswapSwapExactInput_failedMEVCheck()
        external
    {
        address[] memory tokens = new address[](2);
        uint24[] memory poolFees = new uint24[](1);

        tokens[0] = wbnbAddress;
        tokens[1] = cakeAddress;
        poolFees[0] = poolFee;

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(wbnbAddress, 1e18, vaultOwner);

        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.pancakeswapSwapExactInput(
            tokens,
            poolFees,
            1e18,
            false,
            false,
            0
        );
    }

    function test_bnb_pancakeswapLogic_pancakeswapSwapExactInput_shouldReturnZeroIfAmountInIs0()
        external
    {
        address[] memory tokens = new address[](2);
        uint24[] memory poolFees = new uint24[](1);

        tokens[0] = wbnbAddress;
        tokens[1] = cakeAddress;
        poolFees[0] = poolFee;

        vm.prank(address(vault));
        uint256 amountOut = vault.pancakeswapSwapExactInput(
            tokens,
            poolFees,
            0,
            false,
            false,
            0.005e18
        );

        assertEq(amountOut, 0);
    }

    function test_bnb_pancakeswapLogic_pancakeswapSwapExactInput_shouldReturnAmountOut()
        external
    {
        address[] memory tokens = new address[](2);
        uint24[] memory poolFees = new uint24[](1);

        tokens[0] = wbnbAddress;
        tokens[1] = cakeAddress;
        poolFees[0] = poolFee;

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            wbnbAddress,
            0.5e18,
            vaultOwner
        );

        vm.prank(address(vault));
        uint256 amountOut = vault.pancakeswapSwapExactInput(
            tokens,
            poolFees,
            0.5e18,
            false,
            false,
            0.005e18
        );

        assertGt(amountOut, 0);
    }

    function test_bnb_pancakeswapLogic_pancakeswapSwapExactInput_shouldUseAllPossibleTokenInFromVault()
        external
    {
        address[] memory tokens = new address[](2);
        uint24[] memory poolFees = new uint24[](1);

        tokens[0] = wbnbAddress;
        tokens[1] = cakeAddress;
        poolFees[0] = poolFee;

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            wbnbAddress,
            0.5e18,
            vaultOwner
        );

        vm.prank(address(vault));
        vault.pancakeswapSwapExactInput(
            tokens,
            poolFees,
            0,
            true,
            false,
            0.005e18
        );

        assertEq(TransferHelper.safeGetBalance(wbnbAddress, address(vault)), 0);
    }

    function test_bnb_pancakeswapLogic_pancakeswapSwapExactInput_shouldUnwrapWBNBInTheEnd()
        external
    {
        address[] memory tokens = new address[](2);
        uint24[] memory poolFees = new uint24[](1);

        tokens[0] = cakeAddress;
        tokens[1] = wbnbAddress;
        poolFees[0] = poolFee;

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            cakeAddress,
            100e18,
            vaultOwner
        );

        vm.prank(address(vault));
        vault.pancakeswapSwapExactInput(
            tokens,
            poolFees,
            0,
            true,
            true,
            0.005e18
        );

        assertEq(TransferHelper.safeGetBalance(wbnbAddress, address(vault)), 0);
    }

    function test_bnb_pancakeswapLogic_pancakeswapSwapExactInput_shouldDoNothingIfLastTokenNotWNative()
        external
    {
        address[] memory tokens = new address[](2);
        uint24[] memory poolFees = new uint24[](1);

        tokens[0] = wbnbAddress;
        tokens[1] = cakeAddress;
        poolFees[0] = poolFee;

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            wbnbAddress,
            0.5e18,
            vaultOwner
        );

        vm.prank(address(vault));
        vault.pancakeswapSwapExactInput(
            tokens,
            poolFees,
            0,
            true,
            true,
            0.005e18
        );

        assertEq(TransferHelper.safeGetBalance(wbnbAddress, address(vault)), 0);
        assertGt(TransferHelper.safeGetBalance(cakeAddress, address(vault)), 0);
    }

    function test_bnb_pancakeswapLogic_pancakeswapSwapExactInput_shouldRevertIfProvideWrongParams()
        external
    {
        address[] memory tokens = new address[](1);
        uint24[] memory poolFees = new uint24[](0);

        vm.startPrank(address(vault));

        vm.expectRevert(
            IDexBaseLogic.DexLogicLogic_WrongLengthOfTokensArray.selector
        );
        vault.pancakeswapSwapExactInput(
            tokens,
            poolFees,
            0,
            true,
            true,
            0.005e18
        );

        tokens = new address[](2);
        poolFees = new uint24[](0);

        vm.expectRevert(
            IDexBaseLogic.DexLogicLogic_WrongLengthOfPoolFeesArray.selector
        );
        vault.pancakeswapSwapExactInput(
            tokens,
            poolFees,
            0,
            true,
            true,
            0.005e18
        );

        VaultLogic(address(vault)).depositERC20(
            wbnbAddress,
            0.5e18,
            vaultOwner
        );

        poolFees = new uint24[](1);

        tokens[0] = wbnbAddress;
        tokens[1] = wbnbAddress;
        poolFees[0] = poolFee;

        vm.expectRevert();
        vault.pancakeswapSwapExactInput(
            tokens,
            poolFees,
            0,
            true,
            true,
            0.005e18
        );

        tokens[1] = cakeAddress;
        poolFees[0] = poolFee + 1;

        vm.expectRevert();
        vault.pancakeswapSwapExactInput(
            tokens,
            poolFees,
            0,
            true,
            true,
            0.005e18
        );
    }

    // =========================
    // pancakeswapSwapExactOutputSingle
    // =========================

    function test_bnb_pancakeswapLogic_pancakeswapSwapExactOutputSingle_accessControl()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.pancakeswapSwapExactOutputSingle(address(0), address(0), 0, 0, 0);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.pancakeswapSwapExactOutputSingle(address(0), address(0), 0, 0, 0);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.pancakeswapSwapExactOutputSingle(address(0), address(0), 0, 0, 0);
    }

    function test_bnb_pancakeswapLogic_pancakeswapSwapExactOutputSingle_shouldRevertIfTokensNotEnough()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert();
        vault.pancakeswapSwapExactOutputSingle(
            wbnbAddress,
            cakeAddress,
            poolFee,
            5e18,
            0.005e18
        );
    }

    function test_bnb_pancakeswapLogic_pancakeswapSwapExactOutputSingle_failedMEVCheck()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.pancakeswapSwapExactOutputSingle(
            wbnbAddress,
            cakeAddress,
            poolFee,
            5e18,
            0
        );
    }

    function test_bnb_pancakeswapLogic_pancakeswapSwapExactOutputSingle_shouldReturnZeroIfAmountOutIs0()
        external
    {
        vm.prank(address(vault));
        uint256 amountIn = vault.pancakeswapSwapExactOutputSingle(
            wbnbAddress,
            cakeAddress,
            poolFee,
            0,
            0.005e18
        );

        assertEq(amountIn, 0);
    }

    function test_bnb_pancakeswapLogic_pancakeswapSwapExactOutputSingle_shouldReturnAmountIn()
        external
    {
        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(wbnbAddress, 1e18, vaultOwner);

        vm.prank(address(vault));
        uint256 amountIn = vault.pancakeswapSwapExactOutputSingle(
            wbnbAddress,
            cakeAddress,
            poolFee,
            5e18,
            0.005e18
        );

        assertGt(amountIn, 0);
    }

    // =========================
    // pancakeswapSwapToTargetR
    // =========================

    function test_bnb_pancakeswapLogic_pancakeswapSwapToTargetR_accessControl()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.pancakeswapSwapToTargetR(0.0005e18, pool, 0, 0, 0);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.pancakeswapSwapToTargetR(0.0005e18, pool, 0, 0, 0);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.pancakeswapSwapToTargetR(0.0005e18, pool, 0, 0, 0);
    }

    function test_bnb_pancakeswapLogic_pancakeswapSwapToTargetR_failedMEVCheck()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.pancakeswapSwapToTargetR(0, pool, 0, 0, 0);
    }

    function test_bnb_pancakeswapLogic_pancakeswapSwapToTargetR_shouldReturnZeroesIfAmountsAre0()
        external
    {
        uint256 targetR = reg.lens.dexLogicLens.getTargetRE18ForTickRange(
            nftId,
            reg.pancakeswapNFTPositionManager,
            reg.pancakeswapFactory
        );

        vm.prank(address(vault));
        (uint256 amount0, uint256 amount1) = vault.pancakeswapSwapToTargetR(
            0.005e18,
            pool,
            0,
            0,
            targetR
        );

        assertEq(amount0, 0);
        assertEq(amount1, 0);
    }

    function test_bnb_pancakeswapLogic_pancakeswapSwapToTargetR_shouldReturnAmounts()
        external
    {
        uint256 targetR = reg.lens.dexLogicLens.getTargetRE18ForTickRange(
            nftId,
            reg.pancakeswapNFTPositionManager,
            reg.pancakeswapFactory
        );

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            wbnbAddress,
            0.5e18,
            vaultOwner
        );

        vm.prank(address(vault));
        (uint256 amount0, uint256 amount1) = vault.pancakeswapSwapToTargetR(
            0.005e18,
            pool,
            0,
            0.5e18,
            targetR
        );

        assertGt(amount0, 0);
        assertGt(amount1, 0);
    }

    // =========================
    // pancakeswapWithdrawPositionByShares
    // =========================

    function test_bnb_pancakeswapLogic_pancakeswapWithdrawPositionByShares_accessControl()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.pancakeswapWithdrawPositionByShares(nftId, 0, 0);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.pancakeswapWithdrawPositionByShares(nftId, 0, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                address(this)
            )
        );
        vault.pancakeswapWithdrawPositionByShares(nftId, 0, 0);
    }

    function test_bnb_pancakeswapLogic_pancakeswapWithdrawPositionByShares_shouldRevertIfNftDoesNotExists()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert("Invalid token ID");
        vault.pancakeswapWithdrawPositionByShares(type(uint128).max, 0, 0);
    }

    function test_bnb_pancakeswapLogic_pancakeswapWithdrawPositionByShares_failedMEVCheck()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.pancakeswapWithdrawPositionByShares(nftId, 0.5e18, 0);
    }

    function test_bnb_pancakeswapLogic_pancakeswapWithdrawPositionByShares_shouldWithdrawHalf()
        external
    {
        uint256 liquidityBefore = reg.lens.dexLogicLens.getLiquidity(
            nftId,
            reg.pancakeswapNFTPositionManager
        );

        vm.prank(address(vault));
        vault.pancakeswapWithdrawPositionByShares(nftId, 0.5e18, 0.005e18);

        uint256 liquidityAfter = reg.lens.dexLogicLens.getLiquidity(
            nftId,
            reg.pancakeswapNFTPositionManager
        );

        assertApproxEqAbs(
            liquidityBefore - liquidityAfter,
            liquidityAfter,
            1e3
        );
    }

    function test_bnb_pancakeswapLogic_pancakeswapWithdrawPositionByShares_shouldWithdrawAll()
        external
    {
        vm.prank(address(vault));
        vault.pancakeswapWithdrawPositionByShares(nftId, 1e18, 0.005e18);

        uint256 liquidityAfter = reg.lens.dexLogicLens.getLiquidity(
            nftId,
            reg.pancakeswapNFTPositionManager
        );

        assertEq(liquidityAfter, 0);
    }

    function test_bnb_pancakeswapLogic_pancakeswapWithdrawPositionByShares_shouldWithdrawAllIfSharesGtE18()
        external
    {
        vm.prank(address(vault));
        vault.pancakeswapWithdrawPositionByShares(
            nftId,
            type(uint128).max,
            0.005e18
        );

        uint256 liquidityAfter = reg.lens.dexLogicLens.getLiquidity(
            nftId,
            reg.pancakeswapNFTPositionManager
        );

        assertEq(liquidityAfter, 0);
    }

    // =========================
    // pancakeswapWithdrawPositionByLiquidity
    // =========================

    function test_bnb_pancakeswapLogic_pancakeswapWithdrawPositionByLiquidity_accessControl()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.pancakeswapWithdrawPositionByLiquidity(nftId, 0, 0);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.pancakeswapWithdrawPositionByLiquidity(nftId, 0, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                address(this)
            )
        );
        vault.pancakeswapWithdrawPositionByLiquidity(nftId, 0, 0);
    }

    function test_bnb_pancakeswapLogic_pancakeswapWithdrawPositionByLiquidity_shouldRevertIfNftDoesNotExists()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert("Invalid token ID");
        vault.pancakeswapWithdrawPositionByLiquidity(type(uint128).max, 0, 0);
    }

    function test_bnb_pancakeswapLogic_pancakeswapWithdrawPositionByLiquidity_failedMEVCheck()
        external
    {
        uint128 liquidity = reg.lens.dexLogicLens.getLiquidity(
            nftId,
            reg.pancakeswapNFTPositionManager
        );

        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.pancakeswapWithdrawPositionByLiquidity(nftId, liquidity, 0);
    }

    function test_bnb_pancakeswapLogic_pancakeswapWithdrawPositionByLiquidity_shouldWithdrawHalf()
        external
    {
        uint128 liquidityBefore = reg.lens.dexLogicLens.getLiquidity(
            nftId,
            reg.pancakeswapNFTPositionManager
        );

        vm.prank(address(vault));
        vault.pancakeswapWithdrawPositionByLiquidity(
            nftId,
            liquidityBefore >> 1,
            0.005e18
        );

        uint128 liquidityAfter = reg.lens.dexLogicLens.getLiquidity(
            nftId,
            reg.pancakeswapNFTPositionManager
        );

        assertApproxEqAbs(
            liquidityBefore - liquidityAfter,
            liquidityAfter,
            1e3
        );
    }

    function test_bnb_pancakeswapLogic_pancakeswapWithdrawPositionByLiquidity_shouldWithdrawAll()
        external
    {
        uint128 liquidityBefore = reg.lens.dexLogicLens.getLiquidity(
            nftId,
            reg.pancakeswapNFTPositionManager
        );

        vm.prank(address(vault));
        vault.pancakeswapWithdrawPositionByLiquidity(
            nftId,
            liquidityBefore,
            0.005e18
        );

        uint128 liquidityAfter = reg.lens.dexLogicLens.getLiquidity(
            nftId,
            reg.pancakeswapNFTPositionManager
        );

        assertEq(liquidityAfter, 0);
    }

    function test_bnb_pancakeswapLogic_pancakeswapWithdrawPositionByLiquidity_shouldWithdrawAllIfLiquidityGtTotal()
        external
    {
        vm.prank(address(vault));
        vault.pancakeswapWithdrawPositionByLiquidity(
            nftId,
            type(uint128).max,
            0.005e18
        );

        uint128 liquidityAfter = reg.lens.dexLogicLens.getLiquidity(
            nftId,
            reg.pancakeswapNFTPositionManager
        );

        assertEq(liquidityAfter, 0);
    }

    // =========================
    // pancakeswapCollectFees
    // =========================

    function test_bnb_pancakeswapLogic_pancakeswapCollectFees_accessControl()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.pancakeswapCollectFees(nftId);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.pancakeswapCollectFees(nftId);

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                address(this)
            )
        );
        vault.pancakeswapCollectFees(nftId);
    }

    function test_bnb_pancakeswapLogic_pancakeswapCollectFees_shouldRevertIfNftDoesNotExists()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert("ERC721: operator query for nonexistent token");
        vault.pancakeswapCollectFees(type(uint128).max);
    }

    function test_bnb_pancakeswapLogic_pancakeswapCollectFees_shouldCollectAllFees()
        external
    {
        _makeUniSwaps(4);

        (uint256 fee0Before, uint256 fee1Before) = reg.lens.dexLogicLens.fees(
            nftId,
            reg.pancakeswapNFTPositionManager,
            reg.pancakeswapFactory
        );

        assertGt(fee0Before, 0);
        assertGt(fee1Before, 0);

        vm.prank(address(vault));
        vault.pancakeswapCollectFees(nftId);

        (uint256 fee0After, uint256 fee1After) = reg.lens.dexLogicLens.fees(
            nftId,
            reg.pancakeswapNFTPositionManager,
            reg.pancakeswapFactory
        );

        assertApproxEqAbs(fee0After, 0, 1e3);
        assertApproxEqAbs(fee1After, 0, 1e18);
    }

    // ---------------------------------

    function _makeUniSwaps(uint256 numOfSwaps) internal {
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
        for (uint i = 0; i < numOfSwaps; i++) {
            vm.warp(block.timestamp + 60);
            vm.roll(block.number + 5);
            reg.pancakeswapRouter.exactInputSingle(
                IV3SwapRouter.ExactInputSingleParams({
                    tokenIn: wbnbAddress,
                    tokenOut: cakeAddress,
                    fee: poolFee,
                    recipient: donor,
                    amountIn: 1e18,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
            reg.pancakeswapRouter.exactInputSingle(
                IV3SwapRouter.ExactInputSingleParams({
                    tokenIn: cakeAddress,
                    tokenOut: wbnbAddress,
                    fee: poolFee,
                    recipient: donor,
                    amountIn: 1900e18,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
        }
        vm.stopPrank();
    }
}
