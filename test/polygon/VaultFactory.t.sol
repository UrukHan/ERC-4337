// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {ProxyAdmin, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {VaultFactory, IVaultFactory} from "../../src/VaultFactory.sol";
import {IOwnable} from "../../src/external/IOwnable.sol";
import {Vault} from "../../src/vault/Vault.sol";
import {VersionUpgradeLogic, IVersionUpgradeLogic} from "../../src/vault/logics/VersionUpgradeLogic.sol";

import {FullDeploy, Registry, UpgradeLogic, VaultProxyAdmin} from "../../script/FullDeploy.s.sol";

contract VaultFactoryTest is Test, FullDeploy {
    bool isTest = true;

    address vaultOwner = makeAddr("VAULT_OWNER");
    address factoryOwner = makeAddr("FACTORY_OWNER");
    address user = makeAddr("USER");

    Registry.Contracts reg;

    VaultFactory vaultFactory;
    ProxyAdmin proxyAdminVaultFactory;
    Vault vault;

    event VaultCreated(
        address indexed newOwner,
        address indexed vault,
        uint16 vaultId
    );

    function setUp() external {
        vm.createSelectFork(vm.envString("POL_RPC_URL"));

        reg = deploySystemContracts(
            isTest,
            Registry.contractsByChainId(block.chainid)
        );
        vm.startPrank(factoryOwner);
        proxyAdminVaultFactory = new ProxyAdmin();
        reg.vaultFactoryProxyAdmin = proxyAdminVaultFactory;

        uint256 nonce = vm.getNonce(factoryOwner);
        address _vFactory = vm.computeCreateAddress(factoryOwner, nonce + 4);

        reg.logics.versionUpgradeLogic = address(
            new VersionUpgradeLogic(IVaultFactory(_vFactory))
        );

        reg.vaultProxyAdmin = new VaultProxyAdmin(_vFactory);

        (vaultFactory, vault) = addImplementation(reg, true, factoryOwner);

        vaultFactory.setBridgeReceiverContract(address(132456));
        vaultFactory.setEntryPointCreatorAddress(reg.entryPointCreator);

        vm.stopPrank();
    }

    function test_factory_shouldRevertIfInitializeMultipleTimes() external {
        UpgradeLogic upgradeLogic = new UpgradeLogic();
        VaultProxyAdmin vaultProxyAdmin = new VaultProxyAdmin(address(0));
        address proxyAdminFactory = address(new ProxyAdmin());
        VaultFactory _vaultFactory = new VaultFactory(
            address(upgradeLogic),
            address(vaultProxyAdmin)
        );
        _vaultFactory = VaultFactory(
            address(
                new TransparentUpgradeableProxy(
                    address(_vaultFactory),
                    proxyAdminFactory,
                    bytes("")
                )
            )
        );

        _vaultFactory.initialize(address(this));
        assertEq(_vaultFactory.owner(), address(this));
        assertEq(_vaultFactory.upgradeLogic(), address(upgradeLogic));
        assertEq(_vaultFactory.vaultProxyAdmin(), address(vaultProxyAdmin));

        vm.expectRevert(IVaultFactory.VaultFactory_AlreadyInitialized.selector);
        _vaultFactory.initialize(address(this));
    }

    function test_factory_implementationsAndVersions() external {
        assertEq(vaultFactory.versions(), 1);
        assertEq(vaultFactory.implementation(1), address(vault));
    }

    function test_factory_addNewImplementation() external {
        address newImpl = address(1);

        vm.prank(factoryOwner);
        vaultFactory.addNewImplementation(newImpl);

        assertEq(vaultFactory.versions(), 2);
        assertEq(vaultFactory.implementation(2), newImpl);
    }

    function test_factory_addNewImplementation_accessControl() external {
        address newImpl = address(1);

        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOwnable.Ownable_SenderIsNotOwner.selector,
                user
            )
        );
        vaultFactory.addNewImplementation(newImpl);

        vm.stopPrank();
    }

    function test_factory_deploy_cannotDeployWithNotExistenceVersion()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            IVaultFactory.VaultFactory_VersionDoesNotExist.selector
        );
        vaultFactory.deploy(2, 1);
    }

    function test_factory_deploy_shouldRevertIfIdAlreadyUsed() external {
        vm.prank(vaultOwner);
        vaultFactory.deploy(1, 1);

        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IVaultFactory.VaultFactory_IdAlreadyUsed.selector,
                vaultOwner,
                1
            )
        );
        vaultFactory.deploy(1, 1);
    }

    function test_factory_deploy_shouldReturnNewAddressAndEmitsEvent()
        external
    {
        address expectedAddress = vaultFactory.predictDeterministicVaultAddress(
            vaultOwner,
            1
        );

        vm.prank(vaultOwner);
        vm.expectEmit();
        emit VaultCreated(vaultOwner, expectedAddress, 1);
        address newVault = vaultFactory.deploy(1, 1);

        assertEq(newVault, expectedAddress);
    }

    function test_factory_deploy_shouldRevertIfFactoryHasNotImplementations()
        external
    {
        UpgradeLogic upgradeLogic = new UpgradeLogic();
        VaultProxyAdmin vaultProxyAdmin = new VaultProxyAdmin(
            0x1aF7f588A501EA2B5bB3feeFA744892aA2CF00e6
        );
        VaultFactory _vaultFactory = new VaultFactory(
            address(upgradeLogic),
            address(vaultProxyAdmin)
        );

        vm.prank(vaultOwner);
        vm.expectRevert(
            IVaultFactory.VaultFactory_VersionDoesNotExist.selector
        );
        _vaultFactory.deploy(1, 1);
    }

    function test_factory_deploy_shouldDeployLatestVersionIfVersionIs0()
        external
    {
        vm.prank(vaultOwner);
        address newVault = vaultFactory.deploy(0, 1);

        assertEq(
            Vault(payable(address(newVault))).getImplementationAddress(),
            address(vault)
        );
    }

    function test_factory_crossChainDeploy_shouldDeployVaults() external {
        vm.prank(reg.entryPointCreator);
        address newVault = vaultFactory.crossChainDeploy(vaultOwner, 0, 1);

        assertEq(
            Vault(payable(address(newVault))).getImplementationAddress(),
            address(vault)
        );

        vm.prank(address(132456));
        newVault = vaultFactory.crossChainDeploy(vaultOwner, 0, 2);

        assertEq(
            Vault(payable(address(newVault))).getImplementationAddress(),
            address(vault)
        );

        vm.prank(vaultOwner);
        vm.expectRevert(IVaultFactory.VaultFactory_NotAuthorized.selector);
        newVault = vaultFactory.crossChainDeploy(vaultOwner, 0, 3);
    }

    function test_factoryProxy_upgradeFactoryProxy_accessControl() external {
        vm.expectRevert("Ownable: caller is not the owner");
        proxyAdminVaultFactory.upgrade(
            ITransparentUpgradeableProxy(address(vaultFactory)),
            address(1)
        );

        vm.expectRevert("Ownable: caller is not the owner");
        proxyAdminVaultFactory.upgradeAndCall(
            ITransparentUpgradeableProxy(address(vaultFactory)),
            address(1),
            bytes("")
        );
    }

    // =========================
    // Ownable
    // =========================

    function test_factoryProxy_ownable_getOwner() external {
        assertEq(vaultFactory.owner(), factoryOwner);
    }

    function test_factoryProxy_ownable_accessControl() external {
        vm.startPrank(vaultOwner);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOwnable.Ownable_SenderIsNotOwner.selector,
                vaultOwner
            )
        );
        vaultFactory.transferOwnership(vaultOwner);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOwnable.Ownable_SenderIsNotOwner.selector,
                vaultOwner
            )
        );
        vaultFactory.renounceOwnership();

        vm.stopPrank();
    }

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    function test_factoryProxy_transferOwnership_shouldTransferOwnership()
        external
    {
        assertEq(vaultFactory.owner(), factoryOwner);

        vm.prank(factoryOwner);
        vm.expectEmit();
        emit OwnershipTransferred(factoryOwner, vaultOwner);
        vaultFactory.transferOwnership(vaultOwner);

        assertEq(vaultFactory.owner(), vaultOwner);
    }

    function test_factoryProxy_transferOwnership_shouldRevertIfNewOwnerIsAddress0()
        external
    {
        vm.prank(factoryOwner);
        vm.expectRevert(IOwnable.Ownable_NewOwnerCannotBeAddressZero.selector);
        vaultFactory.transferOwnership(address(0));
    }

    function test_factoryProxy_renounceOwnership_shouldRenounceOwnership()
        external
    {
        assertEq(vaultFactory.owner(), factoryOwner);

        vm.prank(factoryOwner);
        vm.expectEmit();
        emit OwnershipTransferred(factoryOwner, address(0));
        vaultFactory.renounceOwnership();

        assertEq(vaultFactory.owner(), address(0));
    }
}
