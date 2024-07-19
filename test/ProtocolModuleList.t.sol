// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

import {ProtocolModuleList, IProtocolModuleList} from "../src/ProtocolModuleList.sol";
import {DeployEngine} from "../script/DeployEngine.sol";

import {IOwnable} from "../src/external/IOwnable.sol";

import {VaultLogic, IVaultLogic} from "../src/vault/logics/VaultLogic.sol";
import {TimeCheckerLogic, ITimeCheckerLogic} from "../src/vault/logics/Checkers/TimeCheckerLogic.sol";

contract ProtocolModuleListTest is Test {
    ProtocolModuleList protocolModuleList;

    address vaultLogicModule;
    bytes4[] vaultLogicModuleSelectors;
    address timeCheckerLogicModule;
    bytes4[] timeCheckerLogicModuleSelectors;
    address[] _mockAddresses;

    address owner = makeAddr("OWNER");
    address user = makeAddr("USER");

    function setUp() external {
        vm.prank(owner);

        protocolModuleList = new ProtocolModuleList();

        vaultLogicModule = address(new VaultLogic());
        timeCheckerLogicModule = address(new TimeCheckerLogic());

        vaultLogicModuleSelectors.push(VaultLogic.depositNative.selector);
        vaultLogicModuleSelectors.push(VaultLogic.withdrawNative.selector);
        vaultLogicModuleSelectors.push(VaultLogic.withdrawTotalNative.selector);
        vaultLogicModuleSelectors.push(VaultLogic.withdrawERC20.selector);
        vaultLogicModuleSelectors.push(VaultLogic.withdrawTotalERC20.selector);
        vaultLogicModuleSelectors.push(VaultLogic.depositERC20.selector);

        timeCheckerLogicModuleSelectors.push(
            TimeCheckerLogic.timeCheckerInitialize.selector
        );
        timeCheckerLogicModuleSelectors.push(
            TimeCheckerLogic.checkTime.selector
        );
        timeCheckerLogicModuleSelectors.push(
            TimeCheckerLogic.checkTimeView.selector
        );
        timeCheckerLogicModuleSelectors.push(
            TimeCheckerLogic.setTimePeriod.selector
        );
        timeCheckerLogicModuleSelectors.push(
            TimeCheckerLogic.getLocalTimeCheckerStorage.selector
        );
    }

    // Add module

    function test_protocolModuleList_addModule_accessControl() external {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOwnable.Ownable_SenderIsNotOwner.selector,
                user
            )
        );
        protocolModuleList.addModule(
            vaultLogicModule,
            vaultLogicModuleSelectors
        );
    }

    function test_protocolModuleList_addModule_shouldRevertIfSelectorsArrayAreNotSorted()
        external
    {
        vm.prank(owner);
        vm.expectRevert(
            IProtocolModuleList
                .ProtocolModuleList_InvalidSelectorsArray
                .selector
        );
        protocolModuleList.addModule(
            vaultLogicModule,
            vaultLogicModuleSelectors
        );

        bytes4[] memory sortedSelectors = DeployEngine.quickSort(
            vaultLogicModuleSelectors,
            _mockAddresses
        );

        sortedSelectors[sortedSelectors.length - 2] = sortedSelectors[
            sortedSelectors.length - 1
        ];
        vm.prank(owner);
        vm.expectRevert(
            IProtocolModuleList
                .ProtocolModuleList_InvalidSelectorsArray
                .selector
        );
        protocolModuleList.addModule(vaultLogicModule, sortedSelectors);
    }

    function test_protocolModuleList_addModule_shouldAddModules() external {
        bytes4[] memory sortedSelectors = DeployEngine.quickSort(
            vaultLogicModuleSelectors,
            _mockAddresses
        );

        vm.prank(owner);
        protocolModuleList.addModule(vaultLogicModule, sortedSelectors);

        assertTrue(protocolModuleList.listedModule(vaultLogicModule));
        (bytes memory selectors, bool inactive) = protocolModuleList
            .getSelectorsByModule(vaultLogicModule);
        assertEq(
            selectors,
            hex"04e941b007b18bde1828686a44004cc185860012db6b5246"
        );
        assertFalse(inactive);

        sortedSelectors = DeployEngine.quickSort(
            timeCheckerLogicModuleSelectors,
            _mockAddresses
        );

        vm.prank(owner);
        protocolModuleList.addModule(timeCheckerLogicModule, sortedSelectors);

        assertTrue(protocolModuleList.listedModule(timeCheckerLogicModule));
        (selectors, inactive) = protocolModuleList.getSelectorsByModule(
            timeCheckerLogicModule
        );
        assertEq(selectors, hex"38ec66234398dedf6e0166c18b8340efe0e8c74f");
        assertFalse(inactive);
    }

    function test_protocolModuleList_addModule_shouldRevertIfModuleAlreadyAdded()
        external
    {
        bytes4[] memory sortedSelectors = DeployEngine.quickSort(
            vaultLogicModuleSelectors,
            _mockAddresses
        );

        vm.prank(owner);
        protocolModuleList.addModule(vaultLogicModule, sortedSelectors);

        assertTrue(protocolModuleList.listedModule(vaultLogicModule));
        (bytes memory selectors, bool inactive) = protocolModuleList
            .getSelectorsByModule(vaultLogicModule);
        assertEq(
            selectors,
            hex"04e941b007b18bde1828686a44004cc185860012db6b5246"
        );
        assertFalse(inactive);

        vm.prank(owner);
        vm.expectRevert(
            IProtocolModuleList.ProtocolModuleList_ModuleAlreadyExists.selector
        );
        protocolModuleList.addModule(vaultLogicModule, sortedSelectors);
    }

    // Activation control

    function test_protocolModuleList_activationModule_accessControl() external {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOwnable.Ownable_SenderIsNotOwner.selector,
                user
            )
        );
        protocolModuleList.deactivateModule(vaultLogicModule);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOwnable.Ownable_SenderIsNotOwner.selector,
                user
            )
        );
        protocolModuleList.activateModule(vaultLogicModule);
    }

    function test_protocolModuleList_activationModule_shouldRevertIfModuleDoesNotExists()
        external
    {
        vm.prank(owner);
        vm.expectRevert(
            IProtocolModuleList.ProtocolModuleList_ModuleDoesNotExists.selector
        );
        protocolModuleList.deactivateModule(vaultLogicModule);

        vm.prank(owner);
        vm.expectRevert(
            IProtocolModuleList.ProtocolModuleList_ModuleDoesNotExists.selector
        );
        protocolModuleList.activateModule(vaultLogicModule);
    }

    function test_protocolModuleList_activationModule_shouldDeactivateAndActivateModule()
        external
    {
        bytes4[] memory sortedSelectors = DeployEngine.quickSort(
            vaultLogicModuleSelectors,
            _mockAddresses
        );

        vm.prank(owner);
        protocolModuleList.addModule(vaultLogicModule, sortedSelectors);

        assertFalse(protocolModuleList.isModuleInactive(vaultLogicModule));

        vm.prank(owner);
        protocolModuleList.deactivateModule(vaultLogicModule);

        assertTrue(protocolModuleList.isModuleInactive(vaultLogicModule));

        vm.prank(owner);
        protocolModuleList.activateModule(vaultLogicModule);

        assertFalse(protocolModuleList.isModuleInactive(vaultLogicModule));
    }
}
