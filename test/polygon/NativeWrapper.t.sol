// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {VaultFactory} from "../../src/VaultFactory.sol";
import {BaseContract} from "../../src/vault/libraries/BaseContract.sol";
import {NativeWrapper, INativeWrapper} from "../../src/vault/logics/OurLogic/helpers/NativeWrapper.sol";
import {VaultLogic} from "../../src/vault/logics/VaultLogic.sol";

import {FullDeploy, Registry, VaultProxyAdmin} from "../../script/FullDeploy.s.sol";

contract NativeWrapperTest is Test, FullDeploy {
    bool isTest = true;

    NativeWrapper vault;
    // mainnet WMATIC
    address wmaticAddress = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

    address vaultOwner = makeAddr("VAULT_OWNER");
    address executor = makeAddr("EXECUTOR");

    function setUp() external {
        vm.createSelectFork(vm.envString("POL_RPC_URL"));

        Registry.Contracts memory reg;

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

        vm.deal(vaultOwner, 15 ether);
        vm.deal(executor, 15 ether);

        vm.startPrank(vaultOwner);
        address vaultProxy = vaultFactory.deploy(1, 1);

        vault = NativeWrapper(vaultProxy);
        VaultLogic(payable(vaultProxy)).depositNative{value: 5 ether}();

        vm.stopPrank();
    }

    function test_nativeWrapper_accessControl() external {
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.wrapNativeFromVaultBalance(1 ether);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.unwrapNative(1 ether);
    }

    function test_nativeWrapper_wrapNative_shouldWrap() external {
        assertEq(IERC20Metadata(wmaticAddress).balanceOf(address(vault)), 0);

        vm.prank(vaultOwner);
        vault.wrapNative{value: 1 ether}();
        assertEq(
            IERC20Metadata(wmaticAddress).balanceOf(address(vault)),
            1 ether
        );
    }

    function test_nativeWrapper_wrapNativeFromVaultBalance_shouldWrap()
        external
    {
        assertEq(IERC20Metadata(wmaticAddress).balanceOf(address(vault)), 0);

        vm.prank(vaultOwner);
        vault.wrapNativeFromVaultBalance(1 ether);
        assertEq(
            IERC20Metadata(wmaticAddress).balanceOf(address(vault)),
            1 ether
        );
    }

    function test_nativeWrapper_unwrapNative_shouldUnwrap() external {
        vm.prank(vaultOwner);
        vault.wrapNativeFromVaultBalance(1 ether);

        assertEq(
            IERC20Metadata(wmaticAddress).balanceOf(address(vault)),
            1 ether
        );

        vm.prank(vaultOwner);
        vault.unwrapNative(1 ether);
        assertEq(IERC20Metadata(wmaticAddress).balanceOf(address(vault)), 0);
    }

    function test_nativeWrapper_insufficientBalanceError() external {
        assertEq(address(vault).balance, 5 ether);
        vm.prank(vaultOwner);
        vm.expectRevert(
            INativeWrapper.NativeWrapper_InsufficientBalance.selector
        );
        vault.wrapNativeFromVaultBalance(6 ether);

        assertEq(IERC20Metadata(wmaticAddress).balanceOf(address(vault)), 0);
        vm.prank(vaultOwner);
        vm.expectRevert(
            INativeWrapper.NativeWrapper_InsufficientBalance.selector
        );
        vault.unwrapNative(6 ether);
    }
}
