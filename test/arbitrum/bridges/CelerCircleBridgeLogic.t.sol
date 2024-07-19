// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {IVaultFactory} from "../../../src/IVaultFactory.sol";
import {CelerCircleBridgeLogic, ICelerCircleBridgeLogic} from "../../../src/vault/logics/OurLogic/bridges/CelerCircleBridgeLogic.sol";
import {VaultProxyAdmin} from "../../../src/VaultProxyAdmin.sol";

import {BaseContract} from "../../../src/vault/libraries/BaseContract.sol";

import {FullDeploy, Registry} from "../../../script/FullDeploy.s.sol";

contract CelerCircleBridgeLogicTest is Test, FullDeploy {
    bool isTest = true;

    Registry.Contracts reg;

    address usdcAddress = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    // wallet for token airdrop
    address donor = 0x02944e3Fb72AA13095d7cebd8389FC74Bec8e48e;

    address vaultOwner = makeAddr("VAULT_OWNER");
    address arbitraryUser = makeAddr("ARBITRARY_USER");

    ICelerCircleBridgeLogic vault;

    function setUp() external {
        vm.createSelectFork(vm.envString("ARB_RPC_URL"));

        vm.startPrank(vaultOwner);
        reg = deploySystemContracts(
            isTest,
            Registry.contractsByChainId(block.chainid)
        );

        uint256 nonce = vm.getNonce(vaultOwner);
        reg.vaultProxyAdmin = new VaultProxyAdmin(
            vm.computeCreateAddress(vaultOwner, nonce + 4)
        );

        reg.logics.celerCircleBridgeLogic = address(
            new CelerCircleBridgeLogic(reg.celerCircleBridgeProxy, usdcAddress)
        );

        (IVaultFactory vaultFactory, ) = addImplementation(
            reg,
            isTest,
            vaultOwner
        );

        vault = ICelerCircleBridgeLogic(vaultFactory.deploy(0, 1));

        vm.stopPrank();

        vm.prank(donor);
        (bool success, ) = usdcAddress.call(
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                address(vault),
                1000e6
            )
        );

        require(success);
    }

    // =========================
    // sendCelerCircleMessage
    // =========================

    function test_arb_celerCircleBridgeLogic_sendCelerCircleMessage_accessControl()
        external
    {
        vm.prank(arbitraryUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                arbitraryUser
            )
        );
        vault.sendCelerCircleMessage(1, 1, address(0));
    }

    function test_arb_celerCircleBridgeLogic_sendCelerCircleMessage_shouldRevertIfTokenBalanceNotEnough()
        external
    {
        deal(address(vault), 10e18);

        vm.prank(address(vault));
        vm.expectRevert("ERC20: transfer amount exceeds balance");

        vault.sendCelerCircleMessage(1, 2000e6, vaultOwner);
    }

    function test_arb_celerCircleBridgeLogic_sendCelerCircleMessage_shouldSuccessfullySendTokensToBridge()
        external
    {
        (, bytes memory data) = usdcAddress.staticcall(
            abi.encodeWithSignature("balanceOf(address)", address(vault))
        );

        assertEq(abi.decode(data, (uint256)), 1000e6);

        vm.prank(address(vault));
        vault.sendCelerCircleMessage(1, 1000e6, vaultOwner);

        (, data) = usdcAddress.staticcall(
            abi.encodeWithSignature("balanceOf(address)", address(vault))
        );

        assertEq(abi.decode(data, (uint256)), 0);
    }

    // =========================
    // sendBatchCelerCircleMessage
    // =========================

    function test_arb_celerCircleBridgeLogic_sendBatchCelerCircleMessage_accessControl()
        external
    {
        address[] memory recipients = new address[](0);
        uint256[] memory exactAmounts = new uint256[](0);

        vm.prank(arbitraryUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                arbitraryUser
            )
        );

        vault.sendBatchCelerCircleMessage(1, exactAmounts, recipients);
    }

    function test_arb_celerCircleBridgeLogic_sendBatchCelerCircleMessage_shouldRevertIfMultisenderArgsNotValid()
        external
    {
        address[] memory recipients = new address[](1);
        uint256[] memory exactAmounts = new uint256[](0);

        vm.prank(address(vault));
        vm.expectRevert(
            ICelerCircleBridgeLogic
                .CelerCircleBridgeLogic_MultisenderArgsNotValid
                .selector
        );

        vault.sendBatchCelerCircleMessage(1, exactAmounts, recipients);
    }

    function test_arb_celerCircleBridgeLogic_sendBatchCelerCircleMessage_shouldRevertIfTokenBalanceNotEnough()
        external
    {
        address[] memory recipients = new address[](2);
        uint256[] memory exactAmounts = new uint256[](2);

        recipients[0] = vaultOwner;
        recipients[1] = address(vault);
        exactAmounts[0] = 500e6;
        exactAmounts[1] = 2000e6;

        vm.prank(address(vault));
        vm.expectRevert("ERC20: transfer amount exceeds balance");

        vault.sendBatchCelerCircleMessage(1, exactAmounts, recipients);
    }

    function test_arb_celerCircleBridgeLogic_sendBatchCelerCircleMessage_shouldSuccessfullySendTokensToBridge()
        external
    {
        address[] memory recipients = new address[](2);
        uint256[] memory exactAmounts = new uint256[](2);

        recipients[0] = vaultOwner;
        recipients[1] = address(vault);
        exactAmounts[0] = 500e6;
        exactAmounts[1] = 500e6;

        (, bytes memory data) = usdcAddress.staticcall(
            abi.encodeWithSignature("balanceOf(address)", address(vault))
        );

        assertEq(abi.decode(data, (uint256)), 1000e6);

        vm.prank(address(vault));
        vault.sendBatchCelerCircleMessage(1, exactAmounts, recipients);

        (, data) = usdcAddress.staticcall(
            abi.encodeWithSignature("balanceOf(address)", address(vault))
        );

        assertEq(abi.decode(data, (uint256)), 0);
    }
}
