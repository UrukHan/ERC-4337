// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPartnerFeeModule} from "../../src/vault/modules/interfaces/IPartnerFeeModule.sol";
import {IPartnerFee} from "../../src/vault/modules/interfaces/IPartnerFee.sol";
import {IVault, ActionModule} from "../../src/vault/interfaces/IVault.sol";
import {BaseContract} from "../../src/vault/libraries/BaseContract.sol";
import {VaultFactory} from "../../src/VaultFactory.sol";
import {EntryPointLogicArbitrum, IEntryPointLogic} from "../../src/vault/logics/arbitrumLogics/EntryPointLogicArbitrum.sol";
import {ExecutionLogicArbitrum, IExecutionLogic} from "../../src/vault/logics/arbitrumLogics/ExecutionLogicArbitrum.sol";
import {ProtocolFees} from "../../src/ProtocolFees.sol";

import {FullDeploy, Registry, VaultProxyAdmin} from "../../script/FullDeploy.s.sol";

contract TestPartnerFeeModule is Test, FullDeploy {
    bool isTest = true;

    IPartnerFeeModule vault;

    Registry.Contracts reg;
    address usdcAddress = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // mainnet USDC
    address wethAddress = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // mainnet WETH
    address donor = 0x3e0199792Ce69DC29A0a36146bFa68bd7C8D6633; // wallet for token airdrop

    address dittoController = makeAddr("ditto controller");
    address partnerController = makeAddr("partner controller");

    address vaultOwner = makeAddr("VAULT_OWNER");
    address user = makeAddr("USER");

    bytes[] multicallData;

    function setUp() external {
        vm.createSelectFork(vm.envString("ARB_RPC_URL"));

        vm.startPrank(donor);
        IERC20(usdcAddress).transfer(vaultOwner, 20000e6);
        vm.stopPrank();

        reg = deploySystemContracts(
            isTest,
            Registry.contractsByChainId(block.chainid)
        );

        reg = deploySystemContracts(
            isTest,
            Registry.contractsByChainId(block.chainid)
        );
        reg = deployAndAddModules(isTest, reg, dittoController);

        reg.protocolFees = new ProtocolFees(vaultOwner);
        reg.logics.entryPointLogic = address(
            new EntryPointLogicArbitrum(reg.automateGelato, reg.protocolFees)
        );
        reg.logics.executionLogic = address(
            new ExecutionLogicArbitrum(reg.protocolFees)
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
        vault = IPartnerFeeModule(vaultFactory.deploy(1, 1));

        address[] memory tokens = new address[](2);
        uint256[] memory fees = new uint256[](2);

        tokens[0] = usdcAddress;
        tokens[1] = wethAddress;
        fees[0] = 1e6;
        fees[1] = 0.5e16;

        vm.prank(dittoController);
        IPartnerFee(reg.partnerFeesContracts.partnerFees).initialize(
            dittoController,
            partnerController,
            dittoController,
            partnerController,
            0.5e18,
            tokens,
            fees
        );

        vm.prank(vaultOwner);
        IERC20(usdcAddress).transfer(address(vault), 10e6);
    }

    // =========================
    // partnerFeeMulticall
    // =========================

    function test_arb_partnerFeeModule_partnerFeeMulticall_shouldRevertIfModuleNotAdded()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(IVault.Vault_FunctionDoesNotExist.selector);
        vault.partnerFeeMulticall(multicallData, usdcAddress);
    }

    function test_arb_partnerFeeModule_partnerFeeMulticall_accessControl()
        external
    {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(
            IVault.moduleAction,
            (reg.modules.partnerFeeModule, ActionModule.ADD)
        );

        vm.prank(vaultOwner);
        IExecutionLogic(address(vault)).multicall(data);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.partnerFeeMulticall(multicallData, usdcAddress);
    }

    function test_arb_partnerFeeModule_partnerFeeMulticall_shouldRevertIfTokenIsNotAllow()
        external
    {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(
            IVault.moduleAction,
            (reg.modules.partnerFeeModule, ActionModule.ADD)
        );

        vm.prank(vaultOwner);
        IExecutionLogic(address(vault)).multicall(data);

        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPartnerFee.PartnerFee_TokenIsNotAllowed.selector,
                address(1)
            )
        );
        vault.partnerFeeMulticall(multicallData, address(1));
    }

    function test_arb_partnerFeeModule_partnerFeeMulticall_shouldRevertIfNotTokensForPay()
        external
    {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(
            IVault.moduleAction,
            (reg.modules.partnerFeeModule, ActionModule.ADD)
        );

        vm.prank(vaultOwner);
        IExecutionLogic(address(vault)).multicall(data);

        vm.prank(vaultOwner);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vault.partnerFeeMulticall(multicallData, wethAddress);
    }

    event Transfer(address indexed from, address indexed to, uint256 value);
    event RewardWithdrawn(
        address indexed token,
        uint256 rewardPartner,
        uint256 rewardDitto
    );

    function test_arb_partnerFeeModule_partnerFeeMulticall_shouldPayFee()
        external
    {
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeCall(
            IVault.moduleAction,
            (reg.modules.partnerFeeModule, ActionModule.ADD)
        );

        vm.prank(vaultOwner);
        IExecutionLogic(address(vault)).multicall(data);

        vm.prank(vaultOwner);
        vm.expectEmit();
        emit Transfer(
            address(vault),
            reg.partnerFeesContracts.partnerFees,
            1e6
        );
        vault.partnerFeeMulticall(multicallData, usdcAddress);

        vm.expectEmit();
        emit Transfer(
            reg.partnerFeesContracts.partnerFees,
            partnerController,
            0.5e6
        );
        vm.expectEmit();
        emit Transfer(
            reg.partnerFeesContracts.partnerFees,
            dittoController,
            0.5e6
        );
        vm.expectEmit();
        emit RewardWithdrawn(usdcAddress, 0.5e6, 0.5e6);
        IPartnerFee(reg.partnerFeesContracts.partnerFees).withdrawReward(
            usdcAddress
        );
    }
}
