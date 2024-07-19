// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {VaultFactory} from "../../src/VaultFactory.sol";
import {VaultLogic, TransferHelper, BaseContract} from "../../src/vault/logics/VaultLogic.sol";

import {FullDeploy, Registry, VaultProxyAdmin} from "../../script/FullDeploy.s.sol";

// Contract w/o receive and fallback
contract TestContract {

}

contract VaultLogicTest is Test, FullDeploy {
    bool isTest = true;

    event DepositNative(address indexed sender, uint256 amount);
    event DepositERC20(
        address indexed sender,
        address indexed token,
        uint256 amount
    );
    event WithdrawNative(address indexed receiver, uint256 amount);
    event WithdrawERC20(
        address indexed receiver,
        address indexed token,
        uint256 amount
    );

    address usdcAddress = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174; // mainnet USDC
    address donor = 0x55CAaBB0d2b704FD0eF8192A7E35D8837e678207; // wallet for token

    VaultLogic vault;
    address testContract;
    address vaultOwner = makeAddr("VAULT_OWNER");
    address user = makeAddr("USER");

    function setUp() external {
        vm.createSelectFork(vm.envString("POL_RPC_URL"));

        testContract = address(new TestContract());

        Registry.Contracts memory reg = deploySystemContracts(
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
        address vaultProxy = vaultFactory.deploy(1, 1);

        vault = VaultLogic(vaultProxy);

        vm.prank(donor);
        IERC20(usdcAddress).transfer(address(vault), 20000e6);
        vm.prank(donor);
        IERC20(usdcAddress).transfer(address(vaultOwner), 20000e6);
    }

    function test_vaultLogic_depositNative() external {
        uint256 balanceBefore = address(vault).balance;
        assertEq(balanceBefore, 0);

        vm.expectEmit();
        emit DepositNative(address(this), 1 ether);
        vault.depositNative{value: 1 ether}();

        uint256 balanceAfter = address(vault).balance;
        assertEq(balanceAfter, 1 ether);
    }

    function test_vaultLogic_depositERC20() external {
        uint256 balanceBefore = TransferHelper.safeGetBalance(
            usdcAddress,
            address(vault)
        );
        assertEq(balanceBefore, 20000e6);

        vm.startPrank(vaultOwner);
        TransferHelper.safeApprove(
            usdcAddress,
            address(vault),
            type(uint128).max
        );

        vm.expectEmit();
        emit DepositERC20(vaultOwner, usdcAddress, 500e6);
        vault.depositERC20(usdcAddress, 500e6, vaultOwner);

        vm.stopPrank();

        uint256 balanceAfter = TransferHelper.safeGetBalance(
            usdcAddress,
            address(vault)
        );
        assertEq(balanceAfter, 20500e6);
    }

    function test_vaultLogic_depositERC20_shouldRevertWithNoAllowance()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            TransferHelper.TransferHelper_SafeTransferFromError.selector
        );
        vault.depositERC20(usdcAddress, 500e6, vaultOwner);
    }

    function test_vaultLogic_depositERC20_accessControl() external {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.depositERC20(usdcAddress, 500e6, vaultOwner);
    }

    function test_vaultLogic_withdrawNative() external {
        vault.depositNative{value: 1 ether}();

        assertEq(address(vault).balance, 1 ether);

        vm.prank(vaultOwner);
        vm.expectEmit();
        emit WithdrawNative(address(this), 0.5 ether);
        vault.withdrawNative(address(this), 0.5 ether);

        assertEq(address(vault).balance, 0.5 ether);
    }

    function test_vaultLogic_withdrawNative_accessControl() external {
        vault.depositNative{value: 1 ether}();

        assertEq(address(vault).balance, 1 ether);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.withdrawNative(user, 0.5 ether);
    }

    function test_vaultLogic_withdrawNative_shouldRevertWithTransferError()
        external
    {
        vault.depositNative{value: 1 ether}();

        assertEq(address(vault).balance, 1 ether);

        vm.prank(vaultOwner);
        vm.expectRevert(
            TransferHelper.TransferHelper_SafeTransferNativeError.selector
        );
        vault.withdrawNative(testContract, 0.5 ether);

        vm.prank(vaultOwner);
        vm.expectRevert(
            TransferHelper.TransferHelper_SafeTransferNativeError.selector
        );
        vault.withdrawNative(testContract, 20 ether);
    }

    function test_vaultLogic_withdrawTotalNative() external {
        vault.depositNative{value: 1 ether}();

        assertEq(address(vault).balance, 1 ether);

        vm.prank(vaultOwner);
        vm.expectEmit();
        emit WithdrawNative(address(this), 1 ether);
        vault.withdrawTotalNative(address(this));

        assertEq(address(vault).balance, 0);
    }

    function test_vaultLogic_withdrawTotalNative_accessControl() external {
        vault.depositNative{value: 1 ether}();

        assertEq(address(vault).balance, 1 ether);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.withdrawTotalNative(user);
    }

    function test_vaultLogic_withdrawERC20() external {
        uint256 balanceBefore = TransferHelper.safeGetBalance(
            usdcAddress,
            address(vault)
        );
        assertEq(balanceBefore, 20000e6);

        vm.prank(vaultOwner);
        vm.expectEmit();
        emit WithdrawERC20(address(this), usdcAddress, 500e6);
        vault.withdrawERC20(usdcAddress, address(this), 500e6);

        uint256 balanceAfter = TransferHelper.safeGetBalance(
            usdcAddress,
            address(vault)
        );
        assertEq(balanceAfter, 19500e6);
    }

    function test_vaultLogic_withdrawERC20_accessControl() external {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.withdrawERC20(usdcAddress, user, 500e6);
    }

    function test_vaultLogic_withdrawTotalERC20() external {
        uint256 balanceBefore = TransferHelper.safeGetBalance(
            usdcAddress,
            address(vault)
        );
        assertEq(balanceBefore, 20000e6);

        vm.prank(vaultOwner);
        vm.expectEmit();
        emit WithdrawERC20(address(this), usdcAddress, 20000e6);
        vault.withdrawTotalERC20(usdcAddress, address(this));

        uint256 balanceAfter = TransferHelper.safeGetBalance(
            usdcAddress,
            address(vault)
        );
        assertEq(balanceAfter, 0);
    }

    function test_vaultLogic_withdrawTotalERC20_accessControl() external {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.withdrawTotalERC20(usdcAddress, user);
    }

    receive() external payable {}
}
