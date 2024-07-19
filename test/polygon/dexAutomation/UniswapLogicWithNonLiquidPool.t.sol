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

import {FullDeploy, Registry, VaultProxyAdmin} from "../../../script/FullDeploy.s.sol";

contract UniswapLogicTest is Test, FullDeploy {
    bool isTest = true;

    UniswapLogic vault;
    Registry.Contracts reg;

    IUniswapV3Pool pool =
        IUniswapV3Pool(0x9F2b55f290fb1dd0c80d685284dbeF91ebEEA480);
    uint24 poolFee;

    // mainnet WETH
    address wethAddress = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    // mainnet WMATIC
    address wmaticAddress = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    // wallet for token airdrop
    address donor = 0x55CAaBB0d2b704FD0eF8192A7E35D8837e678207;

    address vaultOwner = makeAddr("VAULT_OWNER");
    address executor = makeAddr("EXECUTOR");
    address user = makeAddr("USER");

    function setUp() public {
        vm.createSelectFork(vm.envString("POL_RPC_URL"));

        poolFee = pool.fee();

        vm.startPrank(donor);
        TransferHelper.safeTransfer(wethAddress, vaultOwner, 10e18);
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

        IERC20(wmaticAddress).approve(address(vault), type(uint256).max);
        IERC20(wethAddress).approve(address(vault), type(uint256).max);

        AccessControlLogic(address(vault)).grantRole(
            Constants.EXECUTOR_ROLE,
            address(executor)
        );
        vm.stopPrank();
    }

    function test_polygon_uniswapLogic_uniswapSwapExactInputSingle_shouldReturnAmountOut()
        external
    {
        address[] memory tokens = new address[](2);
        uint24[] memory poolFees = new uint24[](1);

        tokens[0] = wethAddress;
        tokens[1] = wmaticAddress;
        poolFees[0] = poolFee;

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).depositERC20(wethAddress, 10e18, vaultOwner);

        vm.prank(address(vault));
        vault.uniswapSwapExactInput(
            tokens,
            poolFees,
            0.1e18,
            false,
            false,
            0.0005e18
        );

        vm.warp(block.timestamp + 3);

        vm.prank(address(vault));
        vault.uniswapSwapExactInput(
            tokens,
            poolFees,
            0.1e18,
            false,
            false,
            0.0005e18
        );

        vm.warp(block.timestamp + 3);

        vm.prank(address(vault));
        vault.uniswapSwapExactInput(
            tokens,
            poolFees,
            0.1e18,
            false,
            false,
            0.0005e18
        );

        vm.warp(block.timestamp + 3);

        tokens[0] = wmaticAddress;
        tokens[1] = wethAddress;

        vm.prank(address(vault));
        vault.uniswapSwapExactInput(
            tokens,
            poolFees,
            100e18,
            false,
            false,
            0.0005e18
        );
    }

    // ---------------------------------

    function _makeUniSwaps(uint256 numOfSwaps) internal {
        vm.startPrank(donor);
        TransferHelper.safeApprove(
            wmaticAddress,
            address(reg.uniswapRouter),
            type(uint256).max
        );
        TransferHelper.safeApprove(
            wethAddress,
            address(reg.uniswapRouter),
            type(uint256).max
        );
        for (uint i = 0; i < numOfSwaps; i++) {
            vm.warp(block.timestamp + 60);
            vm.roll(block.number + 5);
            reg.uniswapRouter.exactInputSingle(
                IV3SwapRouter.ExactInputSingleParams({
                    tokenIn: wmaticAddress,
                    tokenOut: wethAddress,
                    fee: poolFee,
                    recipient: donor,
                    amountIn: 1e18,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: 0
                })
            );
            reg.uniswapRouter.exactInputSingle(
                IV3SwapRouter.ExactInputSingleParams({
                    tokenIn: wethAddress,
                    tokenOut: wmaticAddress,
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
            wethAddress,
            address(reg.uniswapRouter),
            type(uint256).max
        );
        reg.uniswapRouter.exactInputSingle(
            IV3SwapRouter.ExactInputSingleParams({
                tokenIn: wethAddress,
                tokenOut: wmaticAddress,
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
