// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {VaultFactory} from "../../src/VaultFactory.sol";
import {BaseContract} from "../../src/vault/libraries/BaseContract.sol";
import {IVault, ActionModule} from "../../src/vault/interfaces/IVault.sol";
import {IProtocolModuleList} from "../../src/IProtocolModuleList.sol";

import {FullDeploy, Registry, VaultProxyAdmin} from "../../script/FullDeploy.s.sol";

contract ModuleOne is BaseContract {
    bytes32 private immutable MODULE_ONE_STORAGE_POSITION =
        keccak256("ModuleOne.storage");

    struct ModuleOneStorage {
        bool inactive;
    }

    function _getLocalStorage()
        internal
        view
        returns (ModuleOneStorage storage eps)
    {
        bytes32 position = MODULE_ONE_STORAGE_POSITION;
        assembly ("memory-safe") {
            eps.slot := position
        }
    }

    function moduleOneView() external view onlyOwner returns (bool) {
        return _getLocalStorage().inactive;
    }

    function moduleOne() external onlyOwner {
        _getLocalStorage().inactive = !_getLocalStorage().inactive;
    }
}

contract ModuleTwo is BaseContract {
    bytes32 private immutable MODULE_TWO_STORAGE_POSITION =
        keccak256("ModuleTwo.storage");

    struct ModuleTwoStorage {
        bool inactive;
    }

    function _getLocalStorage()
        internal
        view
        returns (ModuleTwoStorage storage eps)
    {
        bytes32 position = MODULE_TWO_STORAGE_POSITION;
        assembly ("memory-safe") {
            eps.slot := position
        }
    }

    function moduleTwoView() external view onlyOwner returns (bool) {
        return _getLocalStorage().inactive;
    }

    function moduleTwo() external onlyOwner {
        _getLocalStorage().inactive = !_getLocalStorage().inactive;
    }
}

contract ModuleTest is Test, FullDeploy {
    bool isTest = true;

    Registry.Contracts reg;

    address vault;

    address vaultOwner = makeAddr("VAULT_OWNER");
    address user = makeAddr("USER");

    address moduleOne;
    address moduleTwo;

    address[] _mockAddresses;

    event ModuleAdded(address moduleAddress);
    event ModuleDeleted(address moduleAddress);

    function setUp() external {
        vm.createSelectFork(vm.envString("POL_RPC_URL"));

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
        vault = vaultFactory.deploy(1, 1);

        vm.stopPrank();

        moduleOne = address(new ModuleOne());
        moduleTwo = address(new ModuleTwo());

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = ModuleOne.moduleOne.selector;
        selectors[1] = ModuleOne.moduleOneView.selector;
        if (selectors[0] > selectors[1]) {
            (selectors[0], selectors[1]) = (selectors[1], selectors[0]);
        }

        IProtocolModuleList(reg.protocolModuleList).addModule(
            moduleOne,
            selectors
        );

        selectors[0] = ModuleTwo.moduleTwo.selector;
        selectors[1] = ModuleTwo.moduleTwoView.selector;
        if (selectors[0] > selectors[1]) {
            (selectors[0], selectors[1]) = (selectors[1], selectors[0]);
        }

        IProtocolModuleList(reg.protocolModuleList).addModule(
            moduleTwo,
            selectors
        );
    }

    function test_polygon_vaultModule_moduleAction_accessControl() external {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        IVault(vault).moduleAction(moduleOne, ActionModule.ADD);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        IVault(vault).moduleAction(moduleOne, ActionModule.REMOVE);
    }

    function test_polygon_vaultModule_moduleAction_shouldRevertIfModuleDoesNotListed()
        external
    {
        address mockModule = makeAddr("MODULE");

        vm.prank(vault);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.Vault_ModuleNotListed.selector,
                mockModule
            )
        );
        IVault(vault).moduleAction(mockModule, ActionModule.ADD);
    }

    function test_polygon_vaultModule_moduleAction_shouldAddModuleToVault()
        external
    {
        vm.prank(vault);
        vm.expectEmit();
        emit ModuleAdded(moduleOne);
        IVault(vault).moduleAction(moduleOne, ActionModule.ADD);

        address[] memory modules = IVault(vault).getModules();
        assertEq(modules[0], moduleOne);

        vm.startPrank(vaultOwner);
        assertFalse(ModuleOne(vault).moduleOneView());
        ModuleOne(vault).moduleOne();
        assertTrue(ModuleOne(vault).moduleOneView());
        vm.stopPrank();

        vm.prank(vault);
        vm.expectEmit();
        emit ModuleAdded(moduleTwo);
        IVault(vault).moduleAction(moduleTwo, ActionModule.ADD);

        modules = IVault(vault).getModules();
        assertEq(modules[1], moduleTwo);

        vm.startPrank(vaultOwner);
        assertFalse(ModuleTwo(vault).moduleTwoView());
        ModuleTwo(vault).moduleTwo();
        assertTrue(ModuleTwo(vault).moduleTwoView());
        vm.stopPrank();
    }

    function test_polygon_vaultModule_moduleAction_shouldRemoveModuleFromVault()
        external
    {
        vm.prank(vault);
        vm.expectEmit();
        emit ModuleAdded(moduleOne);
        IVault(vault).moduleAction(moduleOne, ActionModule.ADD);

        address[] memory modules = IVault(vault).getModules();
        assertEq(modules[0], moduleOne);

        vm.startPrank(vaultOwner);
        assertFalse(ModuleOne(vault).moduleOneView());
        ModuleOne(vault).moduleOne();
        assertTrue(ModuleOne(vault).moduleOneView());
        vm.stopPrank();

        vm.prank(vault);
        vm.expectEmit();
        emit ModuleAdded(moduleTwo);
        IVault(vault).moduleAction(moduleTwo, ActionModule.ADD);

        modules = IVault(vault).getModules();
        assertEq(modules[1], moduleTwo);

        vm.startPrank(vaultOwner);
        assertFalse(ModuleTwo(vault).moduleTwoView());
        ModuleTwo(vault).moduleTwo();
        assertTrue(ModuleTwo(vault).moduleTwoView());
        vm.stopPrank();

        vm.prank(vault);
        vm.expectEmit();
        emit ModuleDeleted(moduleOne);
        IVault(vault).moduleAction(moduleOne, ActionModule.REMOVE);
        modules = IVault(vault).getModules();
        assertEq(modules[0], moduleTwo);

        vm.startPrank(vaultOwner);
        vm.expectRevert(IVault.Vault_FunctionDoesNotExist.selector);
        assertFalse(ModuleOne(vault).moduleOneView());
        vm.expectRevert(IVault.Vault_FunctionDoesNotExist.selector);
        ModuleOne(vault).moduleOne();
        vm.stopPrank();

        vm.prank(vault);
        vm.expectEmit();
        emit ModuleDeleted(moduleTwo);
        IVault(vault).moduleAction(moduleTwo, ActionModule.REMOVE);
        modules = IVault(vault).getModules();
        assertEq(modules.length, 0);
    }

    function test_polygon_vaultModule_moduleAction_shouldRevertIfModuleAlreadyAdded()
        external
    {
        vm.prank(vault);
        IVault(vault).moduleAction(moduleOne, ActionModule.ADD);

        address[] memory modules = IVault(vault).getModules();
        assertEq(modules[0], moduleOne);

        vm.startPrank(vaultOwner);
        assertFalse(ModuleOne(vault).moduleOneView());
        ModuleOne(vault).moduleOne();
        assertTrue(ModuleOne(vault).moduleOneView());
        vm.stopPrank();

        vm.prank(vault);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.Vault_ModuleAlreadyAdded.selector,
                moduleOne
            )
        );
        IVault(vault).moduleAction(moduleOne, ActionModule.ADD);
    }

    function test_polygon_vaultModule_moduleAction_shouldRevertIfModuleDoesNotAdded()
        external
    {
        vm.prank(vault);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.Vault_ModuleDoesNotAdded.selector,
                moduleOne
            )
        );
        IVault(vault).moduleAction(moduleOne, ActionModule.REMOVE);
    }

    function test_polygon_vaultModule_moduleAction_shouldRevertIfModuleIsInactive()
        external
    {
        // first add then toggle inactive
        vm.prank(vault);
        IVault(vault).moduleAction(moduleOne, ActionModule.ADD);

        IProtocolModuleList(reg.protocolModuleList).deactivateModule(moduleOne);

        address[] memory modules = IVault(vault).getModules();
        assertEq(modules[0], moduleOne);

        vm.startPrank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.Vault_ModuleIsInactive.selector,
                moduleOne
            )
        );
        assertFalse(ModuleOne(vault).moduleOneView());
        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.Vault_ModuleIsInactive.selector,
                moduleOne
            )
        );
        ModuleOne(vault).moduleOne();
        vm.stopPrank();

        // first toggle inactive then add

        IProtocolModuleList(reg.protocolModuleList).deactivateModule(moduleTwo);

        vm.prank(vault);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVault.Vault_ModuleIsInactive.selector,
                moduleTwo
            )
        );
        IVault(vault).moduleAction(moduleTwo, ActionModule.ADD);
    }
}
