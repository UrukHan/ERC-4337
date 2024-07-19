// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {IStargateComposer} from "../../../src/vault/interfaces/external/stargate/IStargateComposer.sol";

import {IVaultFactory} from "../../../src/IVaultFactory.sol";
import {StargateLogic, IStargateLogic} from "../../../src/vault/logics/OurLogic/bridges/StargateLogic.sol";
import {VaultProxyAdmin} from "../../../src/VaultProxyAdmin.sol";

import {BaseContract} from "../../../src/vault/libraries/BaseContract.sol";

import {DittoBridgeReceiver} from "../../../src/DittoBridgeReceiver.sol";

import {FullDeploy, Registry} from "../../../script/FullDeploy.s.sol";

contract StargateLogicTest is Test, FullDeploy {
    bool isTest = true;

    address dittoBridgeReceiver;
    Registry.Contracts reg;

    // mainnet USDT
    address usdtAddress = 0x55d398326f99059fF775485246999027B3197955;
    // wallet for token airdrop
    address donor = 0x8894E0a0c962CB723c1976a4421c95949bE2D4E3;

    address vaultOwner = makeAddr("VAULT_OWNER");
    address arbitraryUser = makeAddr("ARBITRARY_USER");

    IStargateLogic vault;

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

        reg.logics.stargateLogic = address(
            new StargateLogic(
                reg.stargateRouter,
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

        vault = IStargateLogic(vaultFactory.deploy(0, 1));

        vm.stopPrank();

        vm.prank(donor);
        (bool success, ) = usdtAddress.call(
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                address(vault),
                10e18
            )
        );

        require(success);
    }

    // =========================
    // sendStargate
    // =========================

    function test_bnb_stargateLogic_sendStargate_accessControl() external {
        vm.prank(arbitraryUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                arbitraryUser
            )
        );
        vault.sendStargateMessage(
            0,
            1,
            1,
            1,
            1,
            1,
            IStargateComposer.lzTxObj(0, 0, bytes("")),
            bytes("")
        );
    }

    function test_bnb_stargateLogic_sendStargate_shouldRevertIfOwnershipTransferred()
        external
    {
        vm.prank(vaultOwner);
        (bool success, ) = address(vault).call(
            abi.encodeWithSignature("transferOwnership(address)", arbitraryUser)
        );
        require(success);

        vm.prank(address(vault));
        vm.expectRevert(
            IStargateLogic.StargateLogic_VaultCannotUseCrossChainLogic.selector
        );
        vault.sendStargateMessage(
            0,
            1,
            1,
            1,
            1,
            1,
            IStargateComposer.lzTxObj(0, 0, bytes("")),
            bytes("")
        );
    }

    function test_bnb_stargateLogic_sendStargate_shouldRevertIfTokenBalanceNotEnough()
        external
    {
        deal(address(vault), 10e18);

        vm.prank(address(vault));
        vm.expectRevert("BEP20: transfer amount exceeds balance");

        vault.sendStargateMessage(
            0,
            109,
            2,
            2,
            1000e18,
            1000e18,
            IStargateComposer.lzTxObj(200000, 0, bytes("")),
            bytes("")
        );
    }

    function test_bnb_stargateLogic_sendStargate_shouldRevertIfNativeCurrencyBalanceNotEnough()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert();
        vault.sendStargateMessage(
            0,
            109,
            2,
            2,
            100e6,
            100e6,
            IStargateComposer.lzTxObj(200000, 0, bytes("")),
            bytes("")
        );
    }

    function test_bnb_stargateLogic_sendStargate_shouldSuccessfullySendTokensToBridge()
        external
    {
        deal(address(vault), 10e18);

        (, bytes memory data) = usdtAddress.staticcall(
            abi.encodeWithSignature("balanceOf(address)", address(vault))
        );

        assertEq(abi.decode(data, (uint256)), 10e18);

        vm.prank(address(vault));
        vault.sendStargateMessage(
            0,
            109,
            2,
            2,
            10e18,
            9.8e6,
            IStargateComposer.lzTxObj(200000, 0, bytes("")),
            bytes("")
        );

        (, data) = usdtAddress.staticcall(
            abi.encodeWithSignature("balanceOf(address)", address(vault))
        );

        assertEq(abi.decode(data, (uint256)), 0);
    }

    // =========================
    // stargateMulticall
    // =========================

    function test_bnb_stargateLogic_stargateMulticall_accessControl() external {
        bytes[] memory mData = new bytes[](1);

        vm.prank(arbitraryUser);
        vm.expectRevert(
            IStargateLogic
                .StargateLogic_OnlyDittoBridgeReceiverCanCallThisMethod
                .selector
        );

        address[] memory recipients = new address[](0);
        uint256[] memory shares = new uint256[](0);

        mData[0] = abi.encodeCall(
            IStargateLogic.stargateMultisender,
            (
                1,
                IStargateLogic.MultisenderParams(1, 1, 1, 1, recipients, shares)
            )
        );

        vault.stargateMulticall(0, mData);
    }

    function test_bnb_stargateLogic_stargateMulticall_shouldSuccessfullySendTokensToBridge()
        external
    {
        deal(address(vault), 10e18);

        (, bytes memory data) = usdtAddress.staticcall(
            abi.encodeWithSignature("balanceOf(address)", address(vault))
        );

        assertEq(abi.decode(data, (uint256)), 10e18);

        bytes[] memory mData = new bytes[](1);

        address[] memory recipients = new address[](2);
        uint256[] memory shares = new uint256[](2);

        recipients[0] = vaultOwner;
        recipients[1] = vaultOwner;
        shares[0] = 0.6e18;
        shares[1] = 0.4e18;

        mData[0] = abi.encodeCall(
            IStargateLogic.stargateMultisender,
            (
                1,
                IStargateLogic.MultisenderParams(
                    109,
                    2,
                    2,
                    0.995e18,
                    recipients,
                    shares
                )
            )
        );

        vm.prank(dittoBridgeReceiver);
        vault.stargateMulticall(10e18, mData);

        (, data) = usdtAddress.staticcall(
            abi.encodeWithSignature("balanceOf(address)", address(vault))
        );

        assertEq(abi.decode(data, (uint256)), 0);
    }

    // =========================
    // stargateMultisender
    // =========================

    function test_bnb_stargateLogic_stargateMultisender_shouldRevertIfSumOfSharesIsNot1e18()
        external
    {
        deal(address(vault), 10e18);

        address[] memory recipients = new address[](1);
        uint256[] memory shares = new uint256[](1);

        recipients[0] = vaultOwner;
        shares[0] = 1.1e18;

        vm.prank(address(vault));
        vm.expectRevert("BEP20: transfer amount exceeds balance");
        vault.stargateMultisender(
            10e18,
            IStargateLogic.MultisenderParams(
                109,
                2,
                2,
                0.98e18,
                recipients,
                shares
            )
        );
    }

    function test_bnb_stargateLogic_stargateMultisender_shouldSuccessfullySendTokensToBridge()
        external
    {
        deal(address(vault), 10e18);

        (, bytes memory data) = usdtAddress.staticcall(
            abi.encodeWithSignature("balanceOf(address)", address(vault))
        );

        assertEq(abi.decode(data, (uint256)), 10e18);

        address[] memory recipients = new address[](2);
        uint256[] memory shares = new uint256[](2);

        recipients[0] = vaultOwner;
        recipients[1] = vaultOwner;
        shares[0] = 0.6e18;
        shares[1] = 0.4e18;

        vm.prank(address(vault));
        vault.stargateMultisender(
            10e18,
            IStargateLogic.MultisenderParams(
                109,
                2,
                2,
                0.98e18,
                recipients,
                shares
            )
        );

        (, data) = usdtAddress.staticcall(
            abi.encodeWithSignature("balanceOf(address)", address(vault))
        );

        assertEq(abi.decode(data, (uint256)), 0);
    }

    function test_bnb_stargateLogic_stargateMultisender_shouldRevertIfMultisenderParamsInvalid()
        external
    {
        address[] memory recipients = new address[](1);
        uint256[] memory shares = new uint256[](2);

        vm.prank(address(vault));
        vm.expectRevert(
            IStargateLogic
                .StargateLogic_MultisenderParamsDoNotMatchInLength
                .selector
        );
        vault.stargateMultisender(
            1,
            IStargateLogic.MultisenderParams(1, 1, 1, 1, recipients, shares)
        );
    }

    function test_bnb_stargateLogic_stargateMultisender_shouldRevertIfVaultHasNotEnoughNativeCurrencyForFees()
        external
    {
        address[] memory recipients = new address[](1);
        uint256[] memory shares = new uint256[](1);

        vm.prank(address(vault));
        vm.expectRevert(
            IStargateLogic.StargateLogic_NotEnoughBalanceForFee.selector
        );

        vault.stargateMultisender(
            10e18,
            IStargateLogic.MultisenderParams(
                109,
                2,
                2,
                1e18,
                recipients,
                shares
            )
        );
    }
}
