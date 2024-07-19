// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {IV3SwapRouter} from "../../../src/vault/interfaces/external/IV3SwapRouter.sol";
import {VaultFactory} from "../../../src/VaultFactory.sol";
import {UniswapLogic} from "../../../src/vault/logics/OurLogic/dexAutomation/UniswapLogic.sol";
import {TransferHelper} from "../../../src/vault/libraries/utils/TransferHelper.sol";
import {AccessControlLogic} from "../../../src/vault/logics/AccessControlLogic.sol";
import {VaultLogic} from "../../../src/vault/logics/VaultLogic.sol";
import {Constants} from "../../../src/vault/libraries/BaseContract.sol";
import {DexLogicLens} from "../../../src/lens/DexLogicLens.sol";

import {FullDeploy, Registry, VaultProxyAdmin} from "../../../script/FullDeploy.s.sol";

contract UniswapLogicTest is Test, FullDeploy {
    bool isTest = true;

    UniswapLogic vault;
    Registry.Contracts reg;

    IUniswapV3Pool pool =
        IUniswapV3Pool(0x4d170f8714367C44787AE98259CE8Adb72240067);
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

        AccessControlLogic(address(vault)).grantRole(
            Constants.EXECUTOR_ROLE,
            address(executor)
        );
        vm.stopPrank();
    }

    function test_bnb_uniswapLogic_uniswapSwapExactInputSingle_shouldReturnAmountOut()
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
            20000e18,
            vaultOwner
        );

        vm.prank(address(vault));
        vault.uniswapSwapExactInput(
            tokens,
            poolFees,
            250e18,
            false,
            false,
            0.0005e18
        );

        vm.warp(block.timestamp + 3);

        vm.prank(address(vault));
        vault.uniswapSwapExactInput(
            tokens,
            poolFees,
            5000e18,
            false,
            false,
            0.0005e18
        );

        vm.warp(block.timestamp + 3);

        vm.prank(address(vault));
        vault.uniswapSwapExactInput(
            tokens,
            poolFees,
            0.25e18,
            false,
            false,
            0.0005e18
        );

        vm.warp(block.timestamp + 3);

        tokens[0] = wbnbAddress;
        tokens[1] = usdtAddress;

        vm.prank(address(vault));
        vault.uniswapSwapExactInput(
            tokens,
            poolFees,
            0.5e18,
            false,
            false,
            0.0005e18
        );
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
                amountIn: 20000e18,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
        vm.stopPrank();
    }
}
