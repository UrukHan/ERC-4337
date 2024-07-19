// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {IVaultFactory} from "../../../src/IVaultFactory.sol";
import {LayerZeroLogic, ILayerZeroLogic} from "../../../src/vault/logics/OurLogic/bridges/LayerZeroLogic.sol";
import {VaultProxyAdmin} from "../../../src/VaultProxyAdmin.sol";

import {BaseContract} from "../../../src/vault/libraries/BaseContract.sol";

import {DittoBridgeReceiver} from "../../../src/DittoBridgeReceiver.sol";

import {FullDeploy, Registry} from "../../../script/FullDeploy.s.sol";

contract LayerZeroLogicTest is Test, FullDeploy {
    bool isTest = true;

    address dittoBridgeReceiver;
    Registry.Contracts reg;

    address vaultOwner = makeAddr("VAULT_OWNER");
    address arbitraryUser = makeAddr("ARBITRARY_USER");

    ILayerZeroLogic vault;

    function setUp() external {
        vm.createSelectFork(vm.envString("BNB_RPC_URL"));

        vm.startPrank(vaultOwner);
        reg = deploySystemContracts(
            isTest,
            Registry.contractsByChainId(block.chainid)
        );

        uint256 nonce = vm.getNonce(vaultOwner);
        reg.vaultProxyAdmin = new VaultProxyAdmin(
            vm.computeCreateAddress(vaultOwner, nonce + 4)
        );

        reg.logics.layerZeroLogic = address(
            new LayerZeroLogic(
                reg.layerZeroEndpoint,
                vm.computeCreateAddress(vaultOwner, nonce + 6)
            )
        );

        (IVaultFactory vaultFactory, ) = addImplementation(
            reg,
            isTest,
            vaultOwner
        );

        dittoBridgeReceiver = address(
            new DittoBridgeReceiver(address(vaultFactory), vaultOwner)
        );

        vault = ILayerZeroLogic(vaultFactory.deploy(0, 1));

        vm.stopPrank();
    }

    // =========================
    // sendLayerZeroMessage
    // =========================

    function test_bnb_layerZeroLogic_sendLayerZeroMessage_accessControl()
        external
    {
        vm.prank(arbitraryUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                arbitraryUser
            )
        );
        vault.sendLayerZeroMessage(
            0,
            1,
            ILayerZeroLogic.LayerZeroTxParams(
                0,
                0,
                address(0),
                address(0),
                false
            ),
            bytes("")
        );
    }

    function test_bnb_layerZeroLogic_sendLayerZeroMessage_shouldRevertIfOwnershipTransferred()
        external
    {
        vm.prank(vaultOwner);
        (bool success, ) = address(vault).call(
            abi.encodeWithSignature("transferOwnership(address)", arbitraryUser)
        );
        require(success);

        vm.prank(address(vault));
        vm.expectRevert(
            ILayerZeroLogic
                .LayerZeroLogic_VaultCannotUseCrossChainLogic
                .selector
        );
        vault.sendLayerZeroMessage(
            0,
            1,
            ILayerZeroLogic.LayerZeroTxParams(
                0,
                0,
                address(0),
                address(0),
                false
            ),
            bytes("")
        );
    }

    function test_bnb_layerZeroLogic_sendLayerZeroMessage_shouldRevertIfNativeCurrencyBalanceNotEnough()
        external
    {
        bytes[] memory data;

        vm.prank(address(vault));
        vm.expectRevert();
        vault.sendLayerZeroMessage(
            0,
            109,
            ILayerZeroLogic.LayerZeroTxParams(
                200000,
                0.1e18,
                vaultOwner,
                address(0),
                false
            ),
            abi.encodeCall(ILayerZeroLogic.layerZeroMulticall, (data))
        );
    }

    function test_bnb_layerZeroLogic_sendLayerZeroMessage_shouldSuccessfullySendMessageToBridge()
        external
    {
        bytes[] memory data;

        deal(address(vault), 10e18);

        vm.prank(address(vault));
        vault.sendLayerZeroMessage(
            0,
            109,
            ILayerZeroLogic.LayerZeroTxParams(
                200000,
                0.1e18,
                vaultOwner,
                address(0),
                false
            ),
            abi.encodeCall(ILayerZeroLogic.layerZeroMulticall, (data))
        );
    }

    function test_bnb_layerZeroLogic_sendLayerZeroMessage_shouldSuccessfullySendMessageToBridgeWithoutAirdrop()
        external
    {
        bytes[] memory data;

        deal(address(vault), 10e18);

        vm.prank(address(vault));
        vault.sendLayerZeroMessage(
            0,
            109,
            ILayerZeroLogic.LayerZeroTxParams(
                200000,
                0,
                address(0),
                address(0),
                false
            ),
            abi.encodeCall(ILayerZeroLogic.layerZeroMulticall, (data))
        );
    }

    // =========================
    // layerZeroMulticall
    // =========================

    function test_bnb_layerZeroLogic_layerZeroMulticall_accessControl()
        external
    {
        bytes[] memory mData = new bytes[](1);

        vm.prank(arbitraryUser);
        vm.expectRevert(
            ILayerZeroLogic
                .LayerZeroLogic_OnlyDittoBridgeReceiverCanCallThisMethod
                .selector
        );

        bytes[] memory data;

        mData[0] = abi.encodeCall(
            ILayerZeroLogic.sendLayerZeroMessage,
            (
                0,
                109,
                ILayerZeroLogic.LayerZeroTxParams(
                    200000,
                    0.1e18,
                    vaultOwner,
                    address(0),
                    false
                ),
                abi.encodeCall(ILayerZeroLogic.layerZeroMulticall, (data))
            )
        );

        vault.layerZeroMulticall(mData);
    }

    function test_bnb_layerZeroLogic_layerZeroMulticall_shouldSuccessfullySendMessageToBridge()
        external
    {
        deal(address(vault), 10e18);

        bytes[] memory data;
        bytes[] memory mData = new bytes[](1);

        mData[0] = abi.encodeCall(
            ILayerZeroLogic.sendLayerZeroMessage,
            (
                0,
                109,
                ILayerZeroLogic.LayerZeroTxParams(
                    200000,
                    0.1e18,
                    vaultOwner,
                    address(0),
                    false
                ),
                abi.encodeCall(ILayerZeroLogic.layerZeroMulticall, (data))
            )
        );

        vm.prank(dittoBridgeReceiver);
        vault.layerZeroMulticall(mData);
    }
}
