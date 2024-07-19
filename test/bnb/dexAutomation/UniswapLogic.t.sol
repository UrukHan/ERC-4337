// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

import {IV3SwapRouter} from "../../../src/vault/interfaces/external/IV3SwapRouter.sol";
import {VaultFactory} from "../../../src/VaultFactory.sol";
import {IDexBaseLogic} from "../../../src/vault/interfaces/ourLogic/dexAutomation/IDexBaseLogic.sol";
import {UniswapLogic} from "../../../src/vault/logics/OurLogic/dexAutomation/UniswapLogic.sol";
import {TransferHelper} from "../../../src/vault/libraries/utils/TransferHelper.sol";
import {DexLogicLib} from "../../../src/vault/libraries/DexLogicLib.sol";
import {AccessControlLogic} from "../../../src/vault/logics/AccessControlLogic.sol";
import {VaultLogic} from "../../../src/vault/logics/VaultLogic.sol";
import {BaseContract, Constants} from "../../../src/vault/libraries/BaseContract.sol";
import {DexLogicLens} from "../../../src/lens/DexLogicLens.sol";

import {FullDeploy, Registry, VaultProxyAdmin} from "../../../script/FullDeploy.s.sol";

contract UniswapLogicTest is Test, FullDeploy {
    bool isTest = true;

    UniswapLogic vault;
    Registry.Contracts reg;

    IUniswapV3Pool pool =
        IUniswapV3Pool(0x6fe9E9de56356F7eDBfcBB29FAB7cd69471a4869);
    uint24 poolFee;

    // mainnet USDT
    address usdtAddress = 0x55d398326f99059fF775485246999027B3197955;
    // mainnet WBNB
    address wbnbAddress = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    // wallet for token airdrop
    address donor = 0x8894E0a0c962CB723c1976a4421c95949bE2D4E3;

    address vaultOwner = makeAddr("VAULT_OWNER");
    address executor = makeAddr("EXECUTOR");
    address user = makeAddr("USER");

    uint256 nftId;

    function setUp() public {
        vm.createSelectFork(vm.envString("BNB_RPC_URL"));

        poolFee = pool.fee();

        vm.startPrank(donor);
        IERC20(usdtAddress).transfer(vaultOwner, 20000e18);
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
        vault = UniswapLogic(vaultFactory.deploy(1, 1));

        IERC20(wbnbAddress).approve(address(vault), type(uint256).max);
        IERC20(usdtAddress).approve(address(vault), type(uint256).max);

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

        uint256 wbnbAmount = reg.lens.dexLogicLens.token1AmountForTargetRE18(
            sqrtPriceX96,
            500e18,
            1e18,
            RTarget,
            poolFee
        );

        uint256 usdtAmount = reg.lens.dexLogicLens.token0AmountForTargetRE18(
            sqrtPriceX96,
            wbnbAmount,
            RTarget
        );

        TransferHelper.safeApprove(
            wbnbAddress,
            address(reg.uniswapNFTPositionManager),
            wbnbAmount
        );
        TransferHelper.safeApprove(
            usdtAddress,
            address(reg.uniswapNFTPositionManager),
            usdtAmount
        );

        INonfungiblePositionManager.MintParams memory _mParams;
        _mParams.token0 = usdtAddress;
        _mParams.token1 = wbnbAddress;
        _mParams.fee = poolFee;
        _mParams.tickLower = minTick;
        _mParams.tickUpper = maxTick;
        _mParams.amount0Desired = usdtAmount;
        _mParams.amount1Desired = wbnbAmount;
        _mParams.recipient = vaultOwner;
        _mParams.deadline = block.timestamp;

        // mint new nft for tests
        (nftId, , , ) = reg.uniswapNFTPositionManager.mint(_mParams);

        reg.uniswapNFTPositionManager.safeTransferFrom(
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
    // uniswapChangeTickRange
    // =========================

    function test_bnb_uniswapLogic_uniswapChangeTickRange_accessControl()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.uniswapChangeTickRange(0, 0, nftId, 0.005e18);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.uniswapChangeTickRange(0, 0, nftId, 0.005e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                address(this)
            )
        );
        vault.uniswapChangeTickRange(0, 0, nftId, 0.005e18);
    }

    function test_bnb_uniswapLogic_uniswapChangeTickRange_shouldSwapTicksIfMinGtMax()
        external
    {
        vm.prank(address(vault));
        uint256 newNftId = vault.uniswapChangeTickRange(
            100,
            -100,
            nftId,
            0.005e18
        );

        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = reg
            .uniswapNFTPositionManager
            .positions(newNftId);

        assertEq(tickLower, -100);
        assertEq(tickUpper, 100);
    }

    function test_bnb_uniswapLogic_uniswapChangeTickRange_shouldNotMintNewNftIfTicksAreSame()
        external
    {
        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = reg
            .uniswapNFTPositionManager
            .positions(nftId);

        vm.prank(address(vault));
        uint256 newNftId = vault.uniswapChangeTickRange(
            tickLower,
            tickUpper,
            nftId,
            0.005e18
        );

        assertEq(newNftId, nftId);

        vm.prank(address(vault));
        newNftId = vault.uniswapChangeTickRange(
            tickUpper,
            tickLower,
            nftId,
            0.005e18
        );

        assertEq(newNftId, nftId);
    }

    function test_bnb_uniswapLogic_uniswapChangeTickRange_shouldSuccessfulChangeTicks()
        external
    {
        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = reg
            .uniswapNFTPositionManager
            .positions(nftId);

        vm.prank(address(vault));
        uint256 newNftId = vault.uniswapChangeTickRange(
            tickLower - 120,
            tickUpper + 120,
            nftId,
            0.005e18
        );

        (, , , , , int24 newTickLower, int24 newTickUpper, , , , , ) = reg
            .uniswapNFTPositionManager
            .positions(newNftId);

        assertEq(newTickLower, tickLower - 120);
        assertEq(newTickUpper, tickUpper + 120);
    }

    function test_bnb_uniswapLogic_uniswapChangeTickRange_failedMEVCheck()
        external
    {
        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = reg
            .uniswapNFTPositionManager
            .positions(nftId);

        _rateDown();

        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.uniswapChangeTickRange(
            tickLower - 120,
            tickUpper + 120,
            nftId,
            0.001e18
        );
    }

    // =========================
    // uniswapMintNft
    // =========================

    function test_bnb_uniswapLogic_uniswapMintNft_accessControl() external {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.uniswapMintNft(pool, 100, 200, 0, 0, false, false, 0);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.uniswapMintNft(pool, 100, 200, 0, 0, false, false, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                address(this)
            )
        );
        vault.uniswapMintNft(pool, 100, 200, 0, 0, false, false, 0);
    }

    function test_bnb_uniswapLogic_uniswapMintNft_shouldSuccessfulMintNewNft_woFlagSwapFlag()
        external
    {
        (, int24 currentTick, , , , , ) = pool.slot0();

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            usdtAddress,
            500e18,
            vaultOwner
        );
        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(wbnbAddress, 1e18, vaultOwner);

        vm.prank(address(vault));
        uint256 newNftId = vault.uniswapMintNft(
            pool,
            ((currentTick - 4000) / 60) * 60,
            ((currentTick + 4000) / 60) * 60,
            500e18,
            1e18,
            false,
            false,
            0.005e18
        );

        (uint256 amount0, uint256 amount1) = reg.lens.dexLogicLens.principal(
            newNftId,
            reg.uniswapNFTPositionManager,
            reg.uniswapFactory
        );

        assertGt(amount0, 0);
        assertGt(amount1, 0);
    }

    function test_bnb_uniswapLogic_uniswapMintNft_shouldSuccessfulMintNewNft_swapFlag()
        external
    {
        (, int24 currentTick, , , , , ) = pool.slot0();

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            usdtAddress,
            500e18,
            vaultOwner
        );
        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(wbnbAddress, 1e18, vaultOwner);

        vm.prank(address(vault));
        uint256 newNftId = vault.uniswapMintNft(
            pool,
            ((currentTick - 4000) / 60) * 60,
            ((currentTick + 4000) / 60) * 60,
            500e18,
            1e18,
            false,
            true,
            0.005e18
        );

        (uint256 amount0, uint256 amount1) = reg.lens.dexLogicLens.principal(
            newNftId,
            reg.uniswapNFTPositionManager,
            reg.uniswapFactory
        );

        assertGt(amount0, 0);
        assertGt(amount1, 0);
    }

    function test_bnb_uniswapLogic_uniswapMintNft_addZeroError() external {
        vm.prank(address(vault));
        vm.expectRevert(
            DexLogicLib.DexLogicLib_ZeroNumberOfTokensCannotBeAdded.selector
        );
        vault.uniswapMintNft(pool, 100, 200, 0, 0, false, false, 1e18);
    }

    function test_bnb_uniswapLogic_uniswapMintNft_failedMEVCheck() external {
        _rateDown();

        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.uniswapMintNft(pool, 100, 200, 0, 0, false, false, 0.001e18);
    }

    function test_bnb_uniswapLogic_uniswapMintNft_shouldSwapTicksIfMinGtMax()
        external
    {
        (, int24 currentTick, , , , , ) = pool.slot0();

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            usdtAddress,
            500e18,
            vaultOwner
        );
        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(wbnbAddress, 1e18, vaultOwner);

        vm.prank(address(vault));
        uint256 newNftId = vault.uniswapMintNft(
            pool,
            ((currentTick + 4000) / 60) * 60,
            ((currentTick - 4000) / 60) * 60,
            500e18,
            1e18,
            false,
            true,
            0.005e18
        );

        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = reg
            .uniswapNFTPositionManager
            .positions(newNftId);

        assertEq(tickLower, ((currentTick - 4000) / 60) * 60);
        assertEq(tickUpper, ((currentTick + 4000) / 60) * 60);
    }

    // =========================
    // uniswapAddLiquidity
    // =========================

    function test_bnb_uniswapLogic_uniswapAddLiquidity_accessControl()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.uniswapAddLiquidity(nftId, 0, 0, false, false, 0.005e18);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.uniswapAddLiquidity(nftId, 0, 0, false, false, 0.005e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                address(this)
            )
        );
        vault.uniswapAddLiquidity(nftId, 0, 0, false, false, 0.005e18);
    }

    function test_bnb_uniswapLogic_uniswapAddLiquidity_shouldRevertIfNftDoesNotExists()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert("Invalid token ID");
        vault.uniswapAddLiquidity(
            type(uint128).max,
            0,
            0,
            false,
            false,
            0.005e18
        );
    }

    function test_bnb_uniswapLogic_uniswapAddLiquidity_shouldSuccessfuluniswapAddLiquidity_woSwapFlag()
        external
    {
        (uint256 amount0Before, uint256 amount1Before) = reg
            .lens
            .dexLogicLens
            .tvl(nftId, reg.uniswapNFTPositionManager, reg.uniswapFactory);

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            usdtAddress,
            500e18,
            vaultOwner
        );
        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(wbnbAddress, 1e18, vaultOwner);

        vm.prank(address(vault));
        vault.uniswapAddLiquidity(nftId, 500e18, 1e18, false, false, 0.005e18);

        (uint256 amount0After, uint256 amount1After) = reg
            .lens
            .dexLogicLens
            .tvl(nftId, reg.uniswapNFTPositionManager, reg.uniswapFactory);

        assertGe(amount0After, amount0Before);
        assertGe(amount1After, amount1Before);
    }

    function test_bnb_uniswapLogic_uniswapAddLiquidity_shouldSuccessfuluniswapAddLiquidity_swapFlag()
        external
    {
        (uint256 amount0Before, uint256 amount1Before) = reg
            .lens
            .dexLogicLens
            .tvl(nftId, reg.uniswapNFTPositionManager, reg.uniswapFactory);

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            usdtAddress,
            500e18,
            vaultOwner
        );
        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(wbnbAddress, 1e18, vaultOwner);

        vm.prank(address(vault));
        vault.uniswapAddLiquidity(nftId, 500e18, 1e18, false, true, 0.005e18);

        (uint256 amount0After, uint256 amount1After) = reg
            .lens
            .dexLogicLens
            .tvl(nftId, reg.uniswapNFTPositionManager, reg.uniswapFactory);

        assertGe(amount0After, amount0Before);
        assertGe(amount1After, amount1Before);
    }

    function test_bnb_uniswapLogic_uniswapAddLiquidity_failedMEVCheck()
        external
    {
        _rateDown();

        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.uniswapAddLiquidity(nftId, 500e18, 1e18, false, false, 0.001e18);
    }

    // =========================
    // uniswapAutoCompound
    // =========================

    function test_bnb_uniswapLogic_uniswapAutoCompound_accessControl()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.uniswapAutoCompound(nftId, 0.005e18);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.uniswapAutoCompound(nftId, 0.005e18);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.uniswapAutoCompound(nftId, 0.005e18);
    }

    function test_bnb_uniswapLogic_uniswapAutoCompound_shouldRevertWithNftWhichNotExists()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert("Invalid token ID");
        vault.uniswapAutoCompound(type(uint128).max, 0.005e18);
    }

    function test_bnb_uniswapLogic_uniswapAutoCompound_failedMEVCheck()
        external
    {
        _rateDown();

        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.uniswapAutoCompound(nftId, 0.001e18);
    }

    function test_bnb_uniswapLogic_uniswapAutoCompound_shouldDoNothingIfNoFeesInNft()
        external
    {
        vm.prank(address(vault));
        vault.uniswapCollectFees(nftId);

        (uint256 amount0Before, uint256 amount1Before) = reg
            .lens
            .dexLogicLens
            .principal(
                nftId,
                reg.uniswapNFTPositionManager,
                reg.uniswapFactory
            );

        vm.prank(address(vault));
        vault.uniswapAutoCompound(nftId, 0.005e18);

        (uint256 amount0After, uint256 amount1After) = reg
            .lens
            .dexLogicLens
            .principal(
                nftId,
                reg.uniswapNFTPositionManager,
                reg.uniswapFactory
            );

        assertEq(amount0Before, amount0After);
        assertEq(amount1Before, amount1After);
    }

    function test_bnb_uniswapLogic_uniswapAutoCompound_shouldSuccessfulUniswapAutoCompoundTwice()
        external
    {
        // do 10 swaps
        _makeUniSwaps(5);

        (uint256 fees0Before, uint256 fees1Before) = reg.lens.dexLogicLens.fees(
            nftId,
            reg.uniswapNFTPositionManager,
            reg.uniswapFactory
        );

        assertNotEq(0, fees0Before);
        assertNotEq(0, fees1Before);

        vm.prank(address(vault));
        vault.uniswapAutoCompound(nftId, 0.05e18);

        (uint256 fees0After, uint256 fees1After) = reg.lens.dexLogicLens.fees(
            nftId,
            reg.uniswapNFTPositionManager,
            reg.uniswapFactory
        );

        assertApproxEqAbs(0, fees0After, 1e18);
        assertApproxEqAbs(0, fees1After, 0.001e18);

        // do 8 swaps
        _makeUniSwaps(4);

        (fees0Before, fees1Before) = reg.lens.dexLogicLens.fees(
            nftId,
            reg.uniswapNFTPositionManager,
            reg.uniswapFactory
        );
        assertNotEq(0, fees0Before);
        assertNotEq(0, fees1Before);

        vm.prank(address(vault));
        vault.uniswapAutoCompound(nftId, 0.05e18);

        (fees0After, fees1After) = reg.lens.dexLogicLens.fees(
            nftId,
            reg.uniswapNFTPositionManager,
            reg.uniswapFactory
        );

        assertApproxEqAbs(0, fees0After, 1e18);
        assertApproxEqAbs(0, fees1After, 0.001e18);
    }

    // =========================
    // uniswapSwapExactInputSingle
    // =========================

    function test_bnb_uniswapLogic_uniswapSwapExactInputSingle_accessControl()
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
        vault.uniswapSwapExactInput(tokens, poolFees, 0, false, false, 0);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.uniswapSwapExactInput(tokens, poolFees, 0, false, false, 0);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.uniswapSwapExactInput(tokens, poolFees, 0, false, false, 0);
    }

    function test_bnb_uniswapLogic_uniswapSwapExactInputSingle_shouldRevertIfTokensNotEnough()
        external
    {
        address[] memory tokens = new address[](2);
        uint24[] memory poolFees = new uint24[](1);

        tokens[0] = wbnbAddress;
        tokens[1] = usdtAddress;
        poolFees[0] = poolFee;

        vm.prank(address(vault));
        vm.expectRevert(
            DexLogicLib.DexLogicLib_NotEnoughTokenBalances.selector
        );

        vault.uniswapSwapExactInput(
            tokens,
            poolFees,
            1e18,
            false,
            false,
            0.005e18
        );
    }

    function test_bnb_uniswapLogic_uniswapSwapExactInputSingle_failedMEVCheck()
        external
    {
        address[] memory tokens = new address[](2);
        uint24[] memory poolFees = new uint24[](1);

        tokens[0] = wbnbAddress;
        tokens[1] = usdtAddress;
        poolFees[0] = poolFee;

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(wbnbAddress, 1e18, vaultOwner);

        _rateDown();

        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.uniswapSwapExactInput(
            tokens,
            poolFees,
            1e18,
            false,
            false,
            0.001e18
        );
    }

    function test_bnb_uniswapLogic_uniswapSwapExactInputSingle_shouldReturnZeroIfAmountInIs0()
        external
    {
        address[] memory tokens = new address[](2);
        uint24[] memory poolFees = new uint24[](1);

        tokens[0] = wbnbAddress;
        tokens[1] = usdtAddress;
        poolFees[0] = poolFee;

        vm.prank(address(vault));
        uint256 amountOut = vault.uniswapSwapExactInput(
            tokens,
            poolFees,
            0,
            false,
            false,
            0.005e18
        );
        assertEq(amountOut, 0);
    }

    function test_bnb_uniswapLogic_uniswapSwapExactInputSingle_shouldReturnAmountOut()
        external
    {
        address[] memory tokens = new address[](2);
        uint24[] memory poolFees = new uint24[](1);

        tokens[0] = wbnbAddress;
        tokens[1] = usdtAddress;
        poolFees[0] = poolFee;

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            wbnbAddress,
            0.5e18,
            vaultOwner
        );

        vm.prank(address(vault));
        uint256 amountOut = vault.uniswapSwapExactInput(
            tokens,
            poolFees,
            0.5e18,
            false,
            false,
            0.005e18
        );

        assertGt(amountOut, 0);
    }

    function test_bnb_uniswapLogic_uniswapSwapExactInput_shouldUseAllPossibleTokenInFromVault()
        external
    {
        address[] memory tokens = new address[](2);
        uint24[] memory poolFees = new uint24[](1);

        tokens[0] = wbnbAddress;
        tokens[1] = usdtAddress;
        poolFees[0] = poolFee;

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            wbnbAddress,
            0.5e18,
            vaultOwner
        );

        vm.prank(address(vault));
        vault.uniswapSwapExactInput(tokens, poolFees, 0, true, false, 0.005e18);

        assertEq(TransferHelper.safeGetBalance(wbnbAddress, address(vault)), 0);
    }

    function test_bnb_uniswapLogic_uniswapSwapExactInput_shouldUnwrapWBNBInTheEnd()
        external
    {
        address[] memory tokens = new address[](2);
        uint24[] memory poolFees = new uint24[](1);

        tokens[0] = usdtAddress;
        tokens[1] = wbnbAddress;
        poolFees[0] = poolFee;

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            usdtAddress,
            100e18,
            vaultOwner
        );

        vm.prank(address(vault));
        vault.uniswapSwapExactInput(tokens, poolFees, 0, true, true, 0.005e18);

        assertEq(TransferHelper.safeGetBalance(wbnbAddress, address(vault)), 0);
    }

    function test_bnb_uniswapLogic_uniswapSwapExactInput_shouldDoNothingIfLastTokenNotWNative()
        external
    {
        address[] memory tokens = new address[](2);
        uint24[] memory poolFees = new uint24[](1);

        tokens[0] = wbnbAddress;
        tokens[1] = usdtAddress;
        poolFees[0] = poolFee;

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            wbnbAddress,
            0.5e18,
            vaultOwner
        );

        vm.prank(address(vault));
        vault.uniswapSwapExactInput(tokens, poolFees, 0, true, true, 0.005e18);

        assertEq(TransferHelper.safeGetBalance(wbnbAddress, address(vault)), 0);
        assertGt(TransferHelper.safeGetBalance(usdtAddress, address(vault)), 0);
    }

    function test_bnb_uniswapLogic_uniswapSwapExactInput_shouldRevertIfProvideWrongParams()
        external
    {
        address[] memory tokens = new address[](1);
        uint24[] memory poolFees = new uint24[](0);

        vm.startPrank(address(vault));

        vm.expectRevert(
            IDexBaseLogic.DexLogicLogic_WrongLengthOfTokensArray.selector
        );
        vault.uniswapSwapExactInput(tokens, poolFees, 0, true, true, 0.005e18);

        tokens = new address[](2);
        poolFees = new uint24[](0);

        vm.expectRevert(
            IDexBaseLogic.DexLogicLogic_WrongLengthOfPoolFeesArray.selector
        );
        vault.uniswapSwapExactInput(tokens, poolFees, 0, true, true, 0.005e18);

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
        vault.uniswapSwapExactInput(tokens, poolFees, 0, true, true, 0.005e18);

        tokens[1] = usdtAddress;
        poolFees[0] = poolFee + 1;

        vm.expectRevert();
        vault.uniswapSwapExactInput(tokens, poolFees, 0, true, true, 0.005e18);
    }

    // =========================
    // uniswapSwapExactOutputSingle
    // =========================

    function test_bnb_uniswapLogic_uniswapSwapExactOutputSingle_accessControl()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.uniswapSwapExactOutputSingle(address(0), address(0), 0, 0, 0);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.uniswapSwapExactOutputSingle(address(0), address(0), 0, 0, 0);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.uniswapSwapExactOutputSingle(address(0), address(0), 0, 0, 0);
    }

    function test_bnb_uniswapLogic_uniswapSwapExactOutputSingle_shouldRevertIfTokensNotEnough()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert();
        vault.uniswapSwapExactOutputSingle(
            wbnbAddress,
            usdtAddress,
            500,
            500e18,
            0.005e18
        );
    }

    function test_bnb_uniswapLogic_uniswapSwapExactOutputSingle_failedMEVCheck()
        external
    {
        _rateDown();

        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.uniswapSwapExactOutputSingle(
            wbnbAddress,
            usdtAddress,
            500,
            500e18,
            0.001e18
        );
    }

    function test_bnb_uniswapLogic_uniswapSwapExactOutputSingle_shouldReturnZeroIfAmountOutIs0()
        external
    {
        vm.prank(address(vault));
        uint256 amountIn = vault.uniswapSwapExactOutputSingle(
            wbnbAddress,
            usdtAddress,
            500,
            0,
            0.005e18
        );

        assertEq(amountIn, 0);
    }

    function test_bnb_uniswapLogic_uniswapSwapExactOutputSingle_shouldReturnAmountIn()
        external
    {
        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(wbnbAddress, 1e18, vaultOwner);

        vm.prank(address(vault));
        uint256 amountIn = vault.uniswapSwapExactOutputSingle(
            wbnbAddress,
            usdtAddress,
            500,
            100e18,
            0.005e18
        );

        assertGt(amountIn, 0);
    }

    // =========================
    // uniswapSwapToTargetR
    // =========================

    function test_bnb_uniswapLogic_uniswapSwapToTargetR_accessControl()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.uniswapSwapToTargetR(0.005e18, pool, 0, 0, 0);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.uniswapSwapToTargetR(0.005e18, pool, 0, 0, 0);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.uniswapSwapToTargetR(0.005e18, pool, 0, 0, 0);
    }

    function test_bnb_uniswapLogic_uniswapSwapToTargetR_failedMEVCheck()
        external
    {
        _rateDown();

        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.uniswapSwapToTargetR(0.001e18, pool, 0, 0, 0);
    }

    function test_bnb_uniswapLogic_uniswapSwapToTargetR_shouldReturnZeroesIfAmountsAre0()
        external
    {
        uint256 targetR = reg.lens.dexLogicLens.getTargetRE18ForTickRange(
            nftId,
            reg.uniswapNFTPositionManager,
            reg.uniswapFactory
        );

        vm.prank(address(vault));
        (uint256 amount0, uint256 amount1) = vault.uniswapSwapToTargetR(
            0.005e18,
            pool,
            0,
            0,
            targetR
        );

        assertEq(amount0, 0);
        assertEq(amount1, 0);
    }

    function test_bnb_uniswapLogic_uniswapSwapToTargetR_shouldReturnAmounts()
        external
    {
        uint256 targetR = reg.lens.dexLogicLens.getTargetRE18ForTickRange(
            nftId,
            reg.uniswapNFTPositionManager,
            reg.uniswapFactory
        );

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            wbnbAddress,
            0.5e18,
            vaultOwner
        );

        vm.prank(address(vault));
        (uint256 amount0, uint256 amount1) = vault.uniswapSwapToTargetR(
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
    // uniswapWithdrawPositionByShares
    // =========================

    function test_bnb_uniswapLogic_uniswapWithdrawPositionByShares_accessControl()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.uniswapWithdrawPositionByShares(nftId, 0, 0);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.uniswapWithdrawPositionByShares(nftId, 0, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                address(this)
            )
        );
        vault.uniswapWithdrawPositionByShares(nftId, 0, 0);
    }

    function test_bnb_uniswapLogic_uniswapWithdrawPositionByShares_shouldRevertIfNftDoesNotExists()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert("Invalid token ID");
        vault.uniswapWithdrawPositionByShares(type(uint128).max, 0, 0);
    }

    function test_bnb_uniswapLogic_uniswapWithdrawPositionByShares_failedMEVCheck()
        external
    {
        _rateDown();

        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.uniswapWithdrawPositionByShares(nftId, 0.5e18, 0.001e18);
    }

    function test_bnb_uniswapLogic_uniswapWithdrawPositionByShares_shouldWithdrawHalf()
        external
    {
        uint256 liquidityBefore = reg.lens.dexLogicLens.getLiquidity(
            nftId,
            reg.uniswapNFTPositionManager
        );

        vm.prank(address(vault));
        vault.uniswapWithdrawPositionByShares(nftId, 0.5e18, 0.005e18);

        uint256 liquidityAfter = reg.lens.dexLogicLens.getLiquidity(
            nftId,
            reg.uniswapNFTPositionManager
        );

        assertApproxEqAbs(
            liquidityBefore - liquidityAfter,
            liquidityAfter,
            1e3
        );
    }

    function test_bnb_uniswapLogic_uniswapWithdrawPositionByShares_shouldWithdrawAll()
        external
    {
        vm.prank(address(vault));
        vault.uniswapWithdrawPositionByShares(nftId, 1e18, 0.005e18);

        uint256 liquidityAfter = reg.lens.dexLogicLens.getLiquidity(
            nftId,
            reg.uniswapNFTPositionManager
        );

        assertEq(liquidityAfter, 0);
    }

    function test_bnb_uniswapLogic_uniswapWithdrawPositionByShares_shouldWithdrawAllIfSharesGtE18()
        external
    {
        vm.prank(address(vault));
        vault.uniswapWithdrawPositionByShares(
            nftId,
            type(uint128).max,
            0.005e18
        );

        uint256 liquidityAfter = reg.lens.dexLogicLens.getLiquidity(
            nftId,
            reg.uniswapNFTPositionManager
        );

        assertEq(liquidityAfter, 0);
    }

    // =========================
    // uniswapWithdrawPositionByLiquidity
    // =========================

    function test_bnb_uniswapLogic_uniswapWithdrawPositionByLiquidity_accessControl()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.uniswapWithdrawPositionByLiquidity(nftId, 0, 0);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.uniswapWithdrawPositionByLiquidity(nftId, 0, 0);

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                address(this)
            )
        );
        vault.uniswapWithdrawPositionByLiquidity(nftId, 0, 0);
    }

    function test_bnb_uniswapLogic_uniswapWithdrawPositionByLiquidity_shouldRevertIfNftDoesNotExists()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert("Invalid token ID");
        vault.uniswapWithdrawPositionByLiquidity(type(uint128).max, 0, 0);
    }

    function test_bnb_uniswapLogic_uniswapWithdrawPositionByLiquidity_failedMEVCheck()
        external
    {
        uint128 liquidity = reg.lens.dexLogicLens.getLiquidity(
            nftId,
            reg.uniswapNFTPositionManager
        );

        _rateDown();

        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.uniswapWithdrawPositionByLiquidity(nftId, liquidity, 0.001e18);
    }

    function test_bnb_uniswapLogic_uniswapWithdrawPositionByLiquidity_shouldWithdrawHalf()
        external
    {
        uint128 liquidityBefore = reg.lens.dexLogicLens.getLiquidity(
            nftId,
            reg.uniswapNFTPositionManager
        );

        vm.prank(address(vault));
        vault.uniswapWithdrawPositionByLiquidity(
            nftId,
            liquidityBefore >> 1,
            0.005e18
        );

        uint128 liquidityAfter = reg.lens.dexLogicLens.getLiquidity(
            nftId,
            reg.uniswapNFTPositionManager
        );

        assertApproxEqAbs(
            liquidityBefore - liquidityAfter,
            liquidityAfter,
            1e3
        );
    }

    function test_bnb_uniswapLogic_uniswapWithdrawPositionByLiquidity_shouldWithdrawAll()
        external
    {
        uint128 liquidityBefore = reg.lens.dexLogicLens.getLiquidity(
            nftId,
            reg.uniswapNFTPositionManager
        );

        vm.prank(address(vault));
        vault.uniswapWithdrawPositionByLiquidity(
            nftId,
            liquidityBefore,
            0.005e18
        );

        uint128 liquidityAfter = reg.lens.dexLogicLens.getLiquidity(
            nftId,
            reg.uniswapNFTPositionManager
        );

        assertEq(liquidityAfter, 0);
    }

    function test_bnb_uniswapLogic_uniswapWithdrawPositionByLiquidity_shouldWithdrawAllIfLiquidityGtTotal()
        external
    {
        vm.prank(address(vault));
        vault.uniswapWithdrawPositionByLiquidity(
            nftId,
            type(uint128).max,
            0.005e18
        );

        uint128 liquidityAfter = reg.lens.dexLogicLens.getLiquidity(
            nftId,
            reg.uniswapNFTPositionManager
        );

        assertEq(liquidityAfter, 0);
    }

    // =========================
    // uniswapCollectFees
    // =========================

    function test_bnb_uniswapLogic_uniswapCollectFees_accessControl() external {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.uniswapCollectFees(nftId);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.uniswapCollectFees(nftId);

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                address(this)
            )
        );
        vault.uniswapCollectFees(nftId);
    }

    function test_bnb_uniswapLogic_uniswapCollectFees_shouldRevertIfNftDoesNotExists()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert("ERC721: operator query for nonexistent token");
        vault.uniswapCollectFees(type(uint128).max);
    }

    function test_bnb_uniswapLogic_uniswapCollectFees_shouldCollectAllFees()
        external
    {
        _makeUniSwaps(4);

        (uint256 fee0Before, uint256 fee1Before) = reg.lens.dexLogicLens.fees(
            nftId,
            reg.uniswapNFTPositionManager,
            reg.uniswapFactory
        );

        assertGt(fee0Before, 0);
        assertGt(fee1Before, 0);

        vm.prank(address(vault));
        vault.uniswapCollectFees(nftId);

        (uint256 fee0After, uint256 fee1After) = reg.lens.dexLogicLens.fees(
            nftId,
            reg.uniswapNFTPositionManager,
            reg.uniswapFactory
        );

        assertApproxEqAbs(fee0After, 0, 1e18);
        assertApproxEqAbs(fee1After, 0, 0.001e18);
    }

    // ---------------------------------

    function _makeUniSwaps(uint256 numOfSwaps) internal {
        vm.startPrank(donor);
        TransferHelper.safeApprove(
            wbnbAddress,
            address(reg.uniswapRouter),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            usdtAddress,
            address(reg.uniswapRouter),
            type(uint256).max
        );
        for (uint i = 0; i < numOfSwaps; i++) {
            vm.warp(block.timestamp + 60);
            vm.roll(block.number + 5);
            reg.uniswapRouter.exactInputSingle(
                IV3SwapRouter.ExactInputSingleParams({
                    tokenIn: wbnbAddress,
                    tokenOut: usdtAddress,
                    fee: poolFee,
                    recipient: donor,
                    amountIn: 1e18,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
            reg.uniswapRouter.exactInputSingle(
                IV3SwapRouter.ExactInputSingleParams({
                    tokenIn: usdtAddress,
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

    // Rate down
    function _rateDown() internal {
        vm.startPrank(donor);
        TransferHelper.safeApprove(
            usdtAddress,
            address(reg.uniswapRouter),
            type(uint256).max
        );
        reg.uniswapRouter.exactInputSingle(
            IV3SwapRouter.ExactInputSingleParams({
                tokenIn: usdtAddress,
                tokenOut: wbnbAddress,
                fee: poolFee,
                recipient: donor,
                amountIn: 25000e18,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
        vm.stopPrank();
    }
}
