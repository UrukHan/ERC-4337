// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

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
import {ExecutionLogic} from "../../../src/vault/logics/ExecutionLogic.sol";
import {BaseContract, Constants} from "../../../src/vault/libraries/BaseContract.sol";
import {DexLogicLens} from "../../../src/lens/DexLogicLens.sol";

import {FullDeploy, Registry, VaultProxyAdmin} from "../../../script/FullDeploy.s.sol";

contract UniswapLogicTest is Test, FullDeploy {
    bool isTest = true;

    UniswapLogic vault;
    Registry.Contracts reg;

    IUniswapV3Pool pool;
    uint24 poolFee;

    // mainnet KLAY
    address wklayAddress = 0x19Aac5f612f524B754CA7e7c41cbFa2E981A4432;
    // mainnet USDT
    address usdtAddress = 0xceE8FAF64bB97a73bb51E115Aa89C17FfA8dD167;
    // wallet for token airdrop
    address donor = 0xfAeeC9B2623b66BBB3545cA24cFc32A8504fcF1B;

    address vaultOwner = makeAddr("VAULT_OWNER");
    address executor = makeAddr("EXECUTOR");
    address user = makeAddr("USER");

    uint256 nftId;

    function setUp() public {
        vm.createSelectFork(vm.envString("KLAY_RPC_URL"));

        deal(vaultOwner, 10000e18);
        deal(donor, 100000e18);

        vm.prank(vaultOwner);
        (bool success, ) = wklayAddress.call{value: 9000e18}(
            abi.encodeWithSignature("deposit()")
        );
        require(success);

        vm.prank(donor);
        TransferHelper.safeTransfer(usdtAddress, vaultOwner, 9000e6);

        vm.prank(donor);
        (success, ) = wklayAddress.call{value: 100000e18}(
            abi.encodeWithSignature("deposit()")
        );
        require(success);

        reg = deploySystemContracts(
            isTest,
            Registry.contractsByChainId(block.chainid)
        );

        pool = IUniswapV3Pool(
            reg.uniswapFactory.getPool(wklayAddress, usdtAddress, 2000)
        );
        poolFee = pool.fee();

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

        TransferHelper.safeApprove(
            usdtAddress,
            address(vault),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            wklayAddress,
            address(vault),
            type(uint256).max
        );

        (, int24 currentTick, , , , , ) = pool.slot0();
        int24 minTick = ((currentTick - 4000) / 40) * 40;
        int24 maxTick = ((currentTick + 4000) / 40) * 40;

        uint256 RTarget = reg.lens.dexLogicLens.getTargetRE18ForTickRange(
            minTick,
            maxTick,
            pool
        );
        uint160 sqrtPriceX96 = reg.lens.dexLogicLens.getCurrentSqrtRatioX96(
            pool
        );

        uint256 usdtAmount = reg.lens.dexLogicLens.token1AmountForTargetRE18(
            sqrtPriceX96,
            1000e18,
            1000e6,
            RTarget,
            poolFee
        );

        uint256 wkalyAmount = reg.lens.dexLogicLens.token0AmountForTargetRE18(
            sqrtPriceX96,
            usdtAmount,
            RTarget
        );

        TransferHelper.safeApprove(
            usdtAddress,
            address(reg.uniswapNFTPositionManager),
            usdtAmount
        );
        TransferHelper.safeApprove(
            wklayAddress,
            address(reg.uniswapNFTPositionManager),
            wkalyAmount
        );

        INonfungiblePositionManager.MintParams memory _mParams;
        _mParams.token0 = wklayAddress;
        _mParams.token1 = usdtAddress;
        _mParams.fee = poolFee;
        _mParams.tickLower = minTick;
        _mParams.tickUpper = maxTick;
        _mParams.amount0Desired = wkalyAmount;
        _mParams.amount1Desired = usdtAmount;
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

    function test_klaytn_uniswapLogic_uniswapChangeTickRange_accessControl()
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

    function test_klaytn_uniswapLogic_uniswapChangeTickRange_shouldSwapTicksIfMinGtMax()
        external
    {
        vm.prank(address(vault));
        uint256 newNftId = vault.uniswapChangeTickRange(
            120,
            -120,
            nftId,
            0.005e18
        );

        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = reg
            .uniswapNFTPositionManager
            .positions(newNftId);

        assertEq(tickLower, -120);
        assertEq(tickUpper, 120);
    }

    function test_klaytn_uniswapLogic_uniswapChangeTickRange_shouldNotMintNewNftIfTicksAreSame()
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

    function test_klaytn_uniswapLogic_uniswapChangeTickRange_shouldSuccessfulChangeTicks()
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

    function test_klaytn_uniswapLogic_uniswapChangeTickRange_failedMEVCheck()
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
            0.005e18
        );
    }

    // =========================
    // uniswapMintNft
    // =========================

    function test_klaytn_uniswapLogic_uniswapMintNft_accessControl() external {
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

    function test_klaytn_uniswapLogic_uniswapMintNft_shouldSuccessfulMintNewNft_woFlagSwapFlag()
        external
    {
        (, int24 currentTick, , , , , ) = pool.slot0();

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            wklayAddress,
            500e18,
            vaultOwner
        );
        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(usdtAddress, 500e6, vaultOwner);

        vm.prank(address(vault));
        uint256 newNftId = vault.uniswapMintNft(
            pool,
            ((currentTick - 4000) / 40) * 40,
            ((currentTick + 4000) / 40) * 40,
            500e18,
            500e6,
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

    function test_klaytn_uniswapLogic_uniswapMintNft_shouldSuccessfulMintNewNft_swapFlag()
        external
    {
        (, int24 currentTick, , , , , ) = pool.slot0();

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            wklayAddress,
            500e18,
            vaultOwner
        );
        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(usdtAddress, 500e6, vaultOwner);

        vm.prank(address(vault));
        uint256 newNftId = vault.uniswapMintNft(
            pool,
            ((currentTick - 4000) / 40) * 40,
            ((currentTick + 4000) / 40) * 40,
            500e18,
            500e6,
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

    function test_klaytn_uniswapLogic_uniswapMintNft_shouldSuccessfulMintNewNft_shouldUseFullBalancesOfTokensFromVault()
        external
    {
        (, int24 currentTick, , , , , ) = pool.slot0();

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            wklayAddress,
            500e18,
            vaultOwner
        );
        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(usdtAddress, 500e6, vaultOwner);

        vm.prank(address(vault));
        uint256 newNftId = vault.uniswapMintNft(
            pool,
            ((currentTick - 4000) / 40) * 40,
            ((currentTick + 4000) / 40) * 40,
            0,
            0,
            true,
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

    function test_klaytn_uniswapLogic_uniswapMintNft_addZeroError() external {
        vm.prank(address(vault));
        vm.expectRevert(
            DexLogicLib.DexLogicLib_ZeroNumberOfTokensCannotBeAdded.selector
        );
        vault.uniswapMintNft(pool, 100, 200, 0, 0, false, false, 1e18);
    }

    function test_klaytn_uniswapLogic_uniswapMintNft_failedMEVCheck() external {
        _rateDown();

        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.uniswapMintNft(pool, 100, 200, 0, 0, false, false, 0.005e18);
    }

    function test_klaytn_uniswapLogic_uniswapMintNft_shouldSwapTicksIfMinGtMax()
        external
    {
        (, int24 currentTick, , , , , ) = pool.slot0();

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            wklayAddress,
            500e18,
            vaultOwner
        );
        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(usdtAddress, 500e6, vaultOwner);

        vm.prank(address(vault));
        uint256 newNftId = vault.uniswapMintNft(
            pool,
            ((currentTick + 4000) / 40) * 40,
            ((currentTick - 4000) / 40) * 40,
            500e18,
            500e6,
            false,
            true,
            0.005e18
        );

        (, , , , , int24 tickLower, int24 tickUpper, , , , , ) = reg
            .uniswapNFTPositionManager
            .positions(newNftId);

        assertEq(tickLower, ((currentTick - 4000) / 40) * 40);
        assertEq(tickUpper, ((currentTick + 4000) / 40) * 40);
    }

    // =========================
    // uniswapAddLiquidity
    // =========================

    function test_klaytn_uniswapLogic_uniswapAddLiquidity_accessControl()
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

    function test_klaytn_uniswapLogic_uniswapAddLiquidity_shouldRevertIfNftDoesNotExists()
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

    function test_klaytn_uniswapLogic_uniswapAddLiquidity_shouldSuccessfulUniswapAddLiquidity_woSwapFlag()
        external
    {
        uint256 tvlInToken1Before = reg.lens.dexLogicLens.tvlInToken1(
            nftId,
            reg.uniswapNFTPositionManager,
            reg.uniswapFactory
        );
        uint256 tvlInToken0Before = reg.lens.dexLogicLens.tvlInToken0(
            nftId,
            reg.uniswapNFTPositionManager,
            reg.uniswapFactory
        );

        (uint256 amount0Before, uint256 amount1Before) = reg
            .lens
            .dexLogicLens
            .tvl(nftId, reg.uniswapNFTPositionManager, reg.uniswapFactory);

        uint160 sqrtPriceX96 = reg.lens.dexLogicLens.getCurrentSqrtRatioX96(
            pool
        );

        uint256 RTarget = reg.lens.dexLogicLens.getTargetRE18ForTickRange(
            nftId,
            reg.uniswapNFTPositionManager,
            reg.uniswapFactory
        );

        uint256 wethAmount = reg.lens.dexLogicLens.token1AmountForTargetRE18(
            sqrtPriceX96,
            500e18,
            500e6,
            RTarget,
            poolFee
        );

        uint256 usdcAmount = reg.lens.dexLogicLens.token0AmountForTargetRE18(
            sqrtPriceX96,
            wethAmount,
            RTarget
        );

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            wklayAddress,
            usdcAmount,
            vaultOwner
        );
        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            usdtAddress,
            wethAmount,
            vaultOwner
        );

        assertApproxEqAbs(
            reg.lens.dexLogicLens.getRE18(
                usdcAmount,
                wethAmount,
                nftId,
                reg.uniswapNFTPositionManager,
                reg.uniswapFactory
            ),
            RTarget,
            100000000000
        );

        console2.logUint(
            reg.dittoOracle.consult(
                wklayAddress,
                1e18,
                usdtAddress,
                poolFee,
                address(reg.uniswapFactory)
            )
        );

        vm.prank(address(vault));
        vault.uniswapAddLiquidity(
            nftId,
            usdcAmount,
            wethAmount,
            false,
            false,
            0.005e18
        );

        uint256 tvlInToken1After = reg.lens.dexLogicLens.tvlInToken1(
            nftId,
            reg.uniswapNFTPositionManager,
            reg.uniswapFactory
        );
        uint256 tvlInToken0After = reg.lens.dexLogicLens.tvlInToken0(
            nftId,
            reg.uniswapNFTPositionManager,
            reg.uniswapFactory
        );

        (uint256 amount0After, uint256 amount1After) = reg
            .lens
            .dexLogicLens
            .tvl(nftId, reg.uniswapNFTPositionManager, reg.uniswapFactory);

        assertGe(amount0After, amount0Before);
        assertGe(amount1After, amount1Before);
        assertGe(tvlInToken1After, tvlInToken1Before);
        assertGe(tvlInToken0After, tvlInToken0Before);
    }

    function test_klaytn_uniswapLogic_uniswapAddLiquidity_shouldSuccessfuluniswapAddLiquidity_swapFlag()
        external
    {
        (uint256 amount0Before, uint256 amount1Before) = reg
            .lens
            .dexLogicLens
            .tvl(nftId, reg.uniswapNFTPositionManager, reg.uniswapFactory);

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            wklayAddress,
            500e18,
            vaultOwner
        );
        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(usdtAddress, 500e6, vaultOwner);

        vm.prank(address(vault));
        vault.uniswapAddLiquidity(nftId, 500e18, 500e6, false, true, 0.005e18);

        (uint256 amount0After, uint256 amount1After) = reg
            .lens
            .dexLogicLens
            .tvl(nftId, reg.uniswapNFTPositionManager, reg.uniswapFactory);

        assertGe(amount0After, amount0Before);
        assertGe(amount1After, amount1Before);
    }

    function test_klaytn_uniswapLogic_uniswapAddLiquidity_failedMEVCheck()
        external
    {
        _rateDown();

        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.uniswapAddLiquidity(nftId, 500e18, 500e6, false, false, 0.005e18);
    }

    function test_klaytn_uniswapLogic_uniswapAddLiquidity_shouldUseFullBalancesOfTokensFromVault()
        external
    {
        (uint256 amount0Before, uint256 amount1Before) = reg
            .lens
            .dexLogicLens
            .tvl(nftId, reg.uniswapNFTPositionManager, reg.uniswapFactory);

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(
            wklayAddress,
            500e18,
            vaultOwner
        );
        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(usdtAddress, 500e6, vaultOwner);

        vm.prank(address(vault));
        vault.uniswapAddLiquidity(nftId, 0, 0, true, true, 0.005e18);

        (uint256 amount0After, uint256 amount1After) = reg
            .lens
            .dexLogicLens
            .tvl(nftId, reg.uniswapNFTPositionManager, reg.uniswapFactory);

        assertGe(amount0After, amount0Before);
        assertGe(amount1After, amount1Before);
    }

    // =========================
    // uniswapAutoCompound
    // =========================

    function test_klaytn_uniswapLogic_uniswapAutoCompound_accessControl()
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

    function test_klaytn_uniswapLogic_uniswapAutoCompound_shouldRevertWithNftWhichNotExists()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert("Invalid token ID");
        vault.uniswapAutoCompound(type(uint128).max, 0.005e18);
    }

    function test_klaytn_uniswapLogic_uniswapAutoCompound_failedMEVCheck()
        external
    {
        _rateDown();

        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.uniswapAutoCompound(nftId, 0.005e18);
    }

    function test_klaytn_uniswapLogic_uniswapAutoCompound_shouldDoNothingIfNoFeesInNft()
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

    function test_klaytn_uniswapLogic_uniswapAutoCompound_shouldSuccessfulUniswapAutoCompoundTwice()
        external
    {
        // do 8 swaps
        _makeUniSwaps(4);

        (uint256 fees0Before, uint256 fees1Before) = reg.lens.dexLogicLens.fees(
            nftId,
            reg.uniswapNFTPositionManager,
            reg.uniswapFactory
        );

        assertNotEq(0, fees0Before);
        assertNotEq(0, fees1Before);

        vm.prank(address(vault));
        vault.uniswapAutoCompound(nftId, 0.005e18);

        (uint256 fees0After, uint256 fees1After) = reg.lens.dexLogicLens.fees(
            nftId,
            reg.uniswapNFTPositionManager,
            reg.uniswapFactory
        );

        assertApproxEqAbs(0, fees0After, 0.5e18);
        assertApproxEqAbs(0, fees1After, 3e6);

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
        vault.uniswapAutoCompound(nftId, 0.005e18);

        (fees0After, fees1After) = reg.lens.dexLogicLens.fees(
            nftId,
            reg.uniswapNFTPositionManager,
            reg.uniswapFactory
        );

        assertApproxEqAbs(0, fees0After, 0.5e18);
        assertApproxEqAbs(0, fees1After, 3e6);
    }

    // =========================
    // uniswapSwapExactInput
    // =========================

    function test_klaytn_uniswapLogic_uniswapSwapExactInput_accessControl()
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

    function test_klaytn_uniswapLogic_uniswapSwapExactInput_shouldRevertIfTokensNotEnough()
        external
    {
        address[] memory tokens = new address[](2);
        uint24[] memory poolFees = new uint24[](1);

        tokens[0] = usdtAddress;
        tokens[1] = wklayAddress;
        poolFees[0] = poolFee;

        vm.prank(address(vault));
        vm.expectRevert(
            DexLogicLib.DexLogicLib_NotEnoughTokenBalances.selector
        );
        vault.uniswapSwapExactInput(
            tokens,
            poolFees,
            500e6,
            false,
            false,
            0.005e18
        );
    }

    function test_klaytn_uniswapLogic_uniswapSwapExactInput_failedMEVCheck()
        external
    {
        address[] memory tokens = new address[](2);
        uint24[] memory poolFees = new uint24[](1);

        tokens[0] = usdtAddress;
        tokens[1] = wklayAddress;
        poolFees[0] = poolFee;

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(usdtAddress, 500e6, vaultOwner);

        _rateDown();

        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.uniswapSwapExactInput(
            tokens,
            poolFees,
            500e6,
            false,
            false,
            0.005e18
        );
    }

    function test_klaytn_uniswapLogic_uniswapSwapExactInput_shouldReturnZeroIfAmountInIs0()
        external
    {
        address[] memory tokens = new address[](2);
        uint24[] memory poolFees = new uint24[](1);

        tokens[0] = usdtAddress;
        tokens[1] = wklayAddress;
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

    function test_klaytn_uniswapLogic_uniswapSwapExactInput_shouldReturnAmountOut()
        external
    {
        address[] memory tokens = new address[](2);
        uint24[] memory poolFees = new uint24[](1);

        tokens[0] = usdtAddress;
        tokens[1] = wklayAddress;
        poolFees[0] = poolFee;

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(usdtAddress, 500e6, vaultOwner);

        vm.prank(address(vault));
        uint256 amountOut = vault.uniswapSwapExactInput(
            tokens,
            poolFees,
            500e6,
            false,
            false,
            0.005e18
        );

        assertGt(amountOut, 0);
    }

    function test_klaytn_uniswapLogic_uniswapSwapExactInput_shouldUseAllPossibleTokenInFromVault()
        external
    {
        address[] memory tokens = new address[](2);
        uint24[] memory poolFees = new uint24[](1);

        tokens[0] = usdtAddress;
        tokens[1] = wklayAddress;
        poolFees[0] = poolFee;

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(usdtAddress, 500e6, vaultOwner);

        vm.prank(address(vault));
        vault.uniswapSwapExactInput(tokens, poolFees, 0, true, false, 0.005e18);

        assertEq(TransferHelper.safeGetBalance(usdtAddress, address(vault)), 0);
    }

    function test_klaytn_uniswapLogic_uniswapSwapExactInput_shouldRevertIfProvideWrongParams()
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

        VaultLogic(address(vault)).depositERC20(usdtAddress, 500e6, vaultOwner);

        poolFees = new uint24[](1);

        tokens[0] = usdtAddress;
        tokens[1] = usdtAddress;
        poolFees[0] = poolFee;

        vm.expectRevert();
        vault.uniswapSwapExactInput(tokens, poolFees, 0, true, true, 0.005e18);

        tokens[1] = wklayAddress;
        poolFees[0] = poolFee + 1;

        vm.expectRevert();
        vault.uniswapSwapExactInput(tokens, poolFees, 0, true, true, 0.005e18);
    }

    // =========================
    // uniswapSwapExactOutputSingle
    // =========================

    function test_klaytn_uniswapLogic_uniswapSwapExactOutputSingle_accessControl()
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

    function test_klaytn_uniswapLogic_uniswapSwapExactOutputSingle_shouldRevertIfTokensNotEnough()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert();
        vault.uniswapSwapExactOutputSingle(
            usdtAddress,
            wklayAddress,
            poolFee,
            500e18,
            0.005e18
        );
    }

    function test_klaytn_uniswapLogic_uniswapSwapExactOutputSingle_failedMEVCheck()
        external
    {
        _rateDown();

        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.uniswapSwapExactOutputSingle(
            usdtAddress,
            wklayAddress,
            poolFee,
            500e18,
            0.005e18
        );
    }

    function test_klaytn_uniswapLogic_uniswapSwapExactOutputSingle_shouldReturnZeroIfAmountOutIs0()
        external
    {
        vm.prank(address(vault));
        uint256 amountIn = vault.uniswapSwapExactOutputSingle(
            usdtAddress,
            wklayAddress,
            poolFee,
            0,
            0.005e18
        );

        assertEq(amountIn, 0);
    }

    function test_klaytn_uniswapLogic_uniswapSwapExactOutputSingle_shouldReturnAmountIn()
        external
    {
        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(usdtAddress, 500e6, vaultOwner);

        vm.prank(address(vault));
        uint256 amountIn = vault.uniswapSwapExactOutputSingle(
            usdtAddress,
            wklayAddress,
            poolFee,
            500e18,
            0.005e18
        );

        assertGt(amountIn, 0);
    }

    // =========================
    // uniswapSwapToTargetR
    // =========================

    function test_klaytn_uniswapLogic_uniswapSwapToTargetR_accessContol()
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

    function test_klaytn_uniswapLogic_uniswapSwapToTargetR_failedMEVCheck()
        external
    {
        _rateDown();

        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.uniswapSwapToTargetR(0.005e18, pool, 0, 0, 0);
    }

    function test_klaytn_uniswapLogic_uniswapSwapToTargetR_shouldReturnZeroesIfAmountsAre0()
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

    function test_klaytn_uniswapLogic_uniswapSwapToTargetR_shouldReturnAmounts()
        external
    {
        uint256 targetR = reg.lens.dexLogicLens.getTargetRE18ForTickRange(
            nftId,
            reg.uniswapNFTPositionManager,
            reg.uniswapFactory
        );

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(usdtAddress, 500e6, vaultOwner);

        vm.prank(address(vault));
        (uint256 amount0, uint256 amount1) = vault.uniswapSwapToTargetR(
            0.005e18,
            pool,
            0,
            500e6,
            targetR
        );

        assertGt(amount0, 0);
        assertGt(amount1, 0);
    }

    // =========================
    // uniswapWithdrawPositionByShares
    // =========================

    function test_klaytn_uniswapLogic_uniswapWithdrawPositionByShares_accessControl()
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

    function test_klaytn_uniswapLogic_uniswapWithdrawPositionByShares_shouldRevertIfNftDoesNotExists()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert("Invalid token ID");
        vault.uniswapWithdrawPositionByShares(type(uint128).max, 0, 0);
    }

    function test_klaytn_uniswapLogic_uniswapWithdrawPositionByShares_failedMEVCheck()
        external
    {
        _rateDown();

        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.uniswapWithdrawPositionByShares(nftId, 0.5e18, 0.005e18);
    }

    function test_klaytn_uniswapLogic_uniswapWithdrawPositionByShares_shouldWithdrawHalf()
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

    function test_klaytn_uniswapLogic_uniswapWithdrawPositionByShares_shouldWithdrawAll()
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

    function test_klaytn_uniswapLogic_uniswapWithdrawPositionByShares_shouldWithdrawAllIfSharesGtE18()
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

    function test_klaytn_uniswapLogic_uniswapWithdrawPositionByLiquidity_accessControl()
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

    function test_klaytn_uniswapLogic_uniswapWithdrawPositionByLiquidity_shouldRevertIfNftDoesNotExists()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert("Invalid token ID");
        vault.uniswapWithdrawPositionByLiquidity(type(uint128).max, 0, 0);
    }

    function test_klaytn_uniswapLogic_uniswapWithdrawPositionByLiquidity_failedMEVCheck()
        external
    {
        uint128 liquidity = reg.lens.dexLogicLens.getLiquidity(
            nftId,
            reg.uniswapNFTPositionManager
        );

        _rateDown();

        vm.prank(address(vault));
        vm.expectRevert(DexLogicLib.MEVCheck_DeviationOfPriceTooHigh.selector);
        vault.uniswapWithdrawPositionByLiquidity(nftId, liquidity, 0.005e18);
    }

    function test_klaytn_uniswapLogic_uniswapWithdrawPositionByLiquidity_shouldWithdrawHalf()
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

    function test_klaytn_uniswapLogic_uniswapWithdrawPositionByLiquidity_shouldWithdrawAll()
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

    function test_klaytn_uniswapLogic_uniswapWithdrawPositionByLiquidity_shouldWithdrawAllIfLiquidityGtTotal()
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

    function test_klaytn_uniswapLogic_uniswapCollectFees_accessControl()
        external
    {
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

    function test_klaytn_uniswapLogic_uniswapCollectFees_shouldRevertIfNftDoesNotExists()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert("ERC721: operator query for nonexistent token");
        vault.uniswapCollectFees(type(uint128).max);
    }

    function test_klaytn_uniswapLogic_uniswapCollectFees_shouldCollectAllFees()
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

        assertApproxEqAbs(fee0After, 0, 1e3);
        assertApproxEqAbs(fee1After, 0, 3e6);
    }

    function test_uniswapLogic_uniswapPermit_shouldAllowApproveInTheMulticall()
        public
    {
        vm.startPrank(vaultOwner);

        (, int24 currentTick, , , , , ) = pool.slot0();
        int24 minTick = ((currentTick - 4000) / 40) * 40;
        int24 maxTick = ((currentTick + 4000) / 40) * 40;

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
            500e18,
            500e6,
            RTarget,
            poolFee
        );

        uint256 usdcAmount = reg.lens.dexLogicLens.token0AmountForTargetRE18(
            sqrtPriceX96,
            wethAmount,
            RTarget
        );

        TransferHelper.safeApprove(
            usdtAddress,
            address(reg.uniswapNFTPositionManager),
            wethAmount
        );
        TransferHelper.safeApprove(
            wklayAddress,
            address(reg.uniswapNFTPositionManager),
            usdcAmount
        );

        INonfungiblePositionManager.MintParams memory _mParams;
        _mParams.token0 = wklayAddress;
        _mParams.token1 = usdtAddress;
        _mParams.fee = poolFee;
        _mParams.tickLower = minTick;
        _mParams.tickUpper = maxTick;
        _mParams.amount0Desired = usdcAmount;
        _mParams.amount1Desired = wethAmount;
        _mParams.recipient = vaultOwner;
        _mParams.deadline = block.timestamp;

        // mint new nft for tests
        (nftId, , , ) = reg.uniswapNFTPositionManager.mint(_mParams);

        (uint96 nonce, , , , , , , , , , , ) = reg
            .uniswapNFTPositionManager
            .positions(nftId);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                reg.uniswapNFTPositionManager.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        reg.uniswapNFTPositionManager.PERMIT_TYPEHASH(),
                        address(vault),
                        nftId,
                        nonce,
                        block.timestamp + 3600
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(keccak256("VAULT_OWNER")),
            digest
        );
        bytes memory permitData = abi.encodeWithSelector(
            reg.uniswapNFTPositionManager.permit.selector,
            address(vault), // spender
            nftId,
            block.timestamp + 3600,
            v,
            r,
            s
        );
        bytes memory transferData = abi.encodeWithSelector(
            reg.uniswapNFTPositionManager.transferFrom.selector,
            vaultOwner,
            address(vault),
            nftId
        );

        bytes[] memory multicallData = new bytes[](2);
        multicallData[0] = abi.encodeWithSelector(
            ExecutionLogic.execute.selector,
            address(reg.uniswapNFTPositionManager),
            0,
            permitData
        );
        multicallData[1] = abi.encodeWithSelector(
            ExecutionLogic.execute.selector,
            address(reg.uniswapNFTPositionManager),
            0,
            transferData
        );

        ExecutionLogic(address(vault)).multicall(multicallData);
        assertEq(reg.uniswapNFTPositionManager.ownerOf(nftId), address(vault));

        vm.stopPrank();
    }

    // ---------------------------------

    function _makeUniSwaps(uint256 numOfSwaps) internal {
        vm.startPrank(donor);
        TransferHelper.safeApprove(
            usdtAddress,
            address(reg.uniswapRouter),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            wklayAddress,
            address(reg.uniswapRouter),
            type(uint256).max
        );
        for (uint i = 0; i < numOfSwaps; i++) {
            vm.warp(block.timestamp + 60);
            vm.roll(block.number + 5);
            reg.uniswapRouter.exactInputSingle(
                IV3SwapRouter.ExactInputSingleParams({
                    tokenIn: usdtAddress,
                    tokenOut: wklayAddress,
                    fee: poolFee,
                    recipient: donor,
                    amountIn: 500e6,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
            reg.uniswapRouter.exactInputSingle(
                IV3SwapRouter.ExactInputSingleParams({
                    tokenIn: wklayAddress,
                    tokenOut: usdtAddress,
                    fee: poolFee,
                    recipient: donor,
                    amountIn: 1000e6,
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
        TransferHelper.safeApprove(
            wklayAddress,
            address(reg.uniswapRouter),
            type(uint256).max
        );
        reg.uniswapRouter.exactInputSingle(
            IV3SwapRouter.ExactInputSingleParams({
                tokenIn: usdtAddress,
                tokenOut: wklayAddress,
                fee: poolFee,
                recipient: donor,
                amountIn: 25000e6,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
        vm.stopPrank();
    }
}
