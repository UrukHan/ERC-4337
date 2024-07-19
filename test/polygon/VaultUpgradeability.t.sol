// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {Vault, IVault} from "../../src/vault/Vault.sol";
import {VersionUpgradeLogic, IVersionUpgradeLogic} from "../../src/vault/logics/VersionUpgradeLogic.sol";
import {AccessControlLogic} from "../../src/vault/logics/AccessControlLogic.sol";
import {Constants, BaseContract} from "../../src/vault/libraries/BaseContract.sol";

import {BinarySearch} from "../../src/vault/libraries/utils/BinarySearch.sol";

import {VaultFactory, IVaultFactory, IVaultProxyAdmin} from "../../src/VaultFactory.sol";
import {FullDeploy, EntryPointLogic, Registry, UpgradeLogic, VaultProxyAdmin} from "../../script/FullDeploy.s.sol";

contract VaultUpgradeabilityTest is Test, FullDeploy {
    bool isTest = true;

    Vault vaultV1;
    Vault vaultV2;

    Registry.Contracts reg;

    IVersionUpgradeLogic vault;
    VaultFactory vaultFactory;
    address vaultOwner = makeAddr("VAULT_OWNER");
    address executor = makeAddr("EXECUTOR");
    address user = makeAddr("USER");

    function setUp() external {
        vm.createSelectFork(vm.envString("POL_RPC_URL"));

        vm.startPrank(vaultOwner);

        reg = deploySystemContracts(
            isTest,
            Registry.contractsByChainId(block.chainid)
        );

        uint256 nonce = vm.getNonce(vaultOwner);
        address _vFactory = vm.computeCreateAddress(vaultOwner, nonce + 4);

        reg.logics.versionUpgradeLogic = address(
            new VersionUpgradeLogic(IVaultFactory(_vFactory))
        );

        reg.vaultProxyAdmin = new VaultProxyAdmin(_vFactory);

        (vaultFactory, vaultV1) = addImplementation(reg, isTest, vaultOwner);

        address vaultProxy;
        vaultProxy = vaultFactory.deploy(1, 1);
        vault = IVersionUpgradeLogic(vaultProxy);

        AccessControlLogic(vaultProxy).grantRole(
            Constants.EXECUTOR_ROLE,
            executor
        );

        bytes4[] memory selectors;
        address[] memory logicAddresses;
        // Empty V2 (without logics and selectors)
        vaultV2 = new Vault(selectors, logicAddresses, address(0));
        vaultFactory.addNewImplementation(address(vaultV2));

        vm.stopPrank();
    }

    function test_upgrade_accessControl() external {
        vm.prank(executor);
        vm.expectRevert(
            IVaultProxyAdmin.VaultProxyAdmin_SenderIsNotVaultOwner.selector
        );
        reg.vaultProxyAdmin.upgrade(address(vault), 2);

        vm.prank(user);
        vm.expectRevert(
            IVaultProxyAdmin.VaultProxyAdmin_SenderIsNotVaultOwner.selector
        );
        reg.vaultProxyAdmin.upgrade(address(vault), 2);
    }

    function test_upgrade_shouldRevertWithNonExistenceVersion() external {
        vm.prank(vaultOwner);
        vm.expectRevert(
            IVaultProxyAdmin.VaultProxyAdmin_VersionDoesNotExist.selector
        );
        reg.vaultProxyAdmin.upgrade(address(vault), 3);
    }

    function test_upgrade_shouldRevertWithUpgradeToSameImplementation()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            IVaultProxyAdmin
                .VaultProxyAdmin_CannotUpdateToCurrentVersion
                .selector
        );
        reg.vaultProxyAdmin.upgrade(address(vault), 1);
    }

    event ImplementationChanged(address newImplementation);

    function test_deployViaFactory_shouldSuccessfulChangeImplAndEmitEvent()
        external
    {
        vm.prank(vaultOwner);
        vm.expectEmit();
        emit ImplementationChanged(address(vaultV1));
        vaultFactory.deploy(1, 2);
    }

    function test_upgrade_shouldSuccessfulChangeImplAndEmitEvent() external {
        address implementationBefore = Vault(payable(address(vault)))
            .getImplementationAddress();
        assertEq(implementationBefore, address(vaultV1));

        vm.prank(vaultOwner);
        vm.expectEmit();
        emit ImplementationChanged(address(vaultV2));
        reg.vaultProxyAdmin.upgrade(address(vault), 2);

        address implementationAfter = Vault(payable(address(vault)))
            .getImplementationAddress();
        assertEq(implementationAfter, address(vaultV2));
    }

    function test_upgrade_downgradeVersion() external {
        address implementationBefore = Vault(payable(address(vault)))
            .getImplementationAddress();
        assertEq(implementationBefore, address(vaultV1));

        vm.prank(vaultOwner);
        reg.vaultProxyAdmin.upgrade(address(vault), 2);

        vm.expectRevert(IVault.Vault_FunctionDoesNotExist.selector);
        EntryPointLogic(address(vault)).isActive();

        address implementationAfter = Vault(payable(address(vault)))
            .getImplementationAddress();
        assertEq(implementationAfter, address(vaultV2));

        vm.prank(vaultOwner);
        reg.vaultProxyAdmin.upgrade(address(vault), 1);

        implementationBefore = Vault(payable(address(vault)))
            .getImplementationAddress();
        assertEq(implementationBefore, address(vaultV1));
        assertTrue(EntryPointLogic(address(vault)).isActive());
    }

    function test_proxyAdmin_cannotSetImplementationIfCallNotFromFactor()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            IVaultProxyAdmin.VaultProxyAdmin_CallerIsNotFactory.selector
        );
        reg.vaultProxyAdmin.initializeImplementation(
            address(vault),
            address(2)
        );
    }

    // Vault

    function test_vault_shouldSetOwner() external {
        address owner = AccessControlLogic(address(vault)).owner();
        assertTrue(owner == vaultOwner);
    }

    function test_vault_upgradeVersion_accessControl() external {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.upgradeVersion(2);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.upgradeVersion(2);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.upgradeVersion(2);
    }

    function test_vault_upgradeVersion_shouldRevertIfVersionDoesNotExists()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert(
            IVersionUpgradeLogic
                .VersionUpgradeLogic_VersionDoesNotExist
                .selector
        );
        vault.upgradeVersion(0);

        vm.prank(address(vault));
        vm.expectRevert(
            IVersionUpgradeLogic
                .VersionUpgradeLogic_VersionDoesNotExist
                .selector
        );
        vault.upgradeVersion(3);
    }

    function test_vault_upgradeVersion_shouldRevertIfTryingToUpgradeToTheSameImpl()
        external
    {
        vm.prank(address(vault));
        vm.expectRevert(
            IVersionUpgradeLogic
                .VersionUpgradeLogic_CannotUpdateToCurrentVersion
                .selector
        );
        vault.upgradeVersion(1);
    }

    function test_vault_upgradeVersion_shouldSuccessfulChangeImplAndEmitEvent()
        external
    {
        assertEq(
            Vault(payable(address(vault))).getImplementationAddress(),
            address(vaultV1)
        );

        vm.prank(address(vault));
        vm.expectEmit();
        emit ImplementationChanged(address(vaultV2));
        vault.upgradeVersion(2);

        assertEq(
            Vault(payable(address(vault))).getImplementationAddress(),
            address(vaultV2)
        );
    }

    function test_vault_deploy_shouldRevertWithInvalidConstructorData()
        external
    {
        // array length not equal
        bytes4[] memory selectors = new bytes4[](1);
        address[] memory logicAddresses;

        vm.expectRevert(IVault.Vault_InvalidConstructorData.selector);
        new Vault(selectors, logicAddresses, address(0));

        logicAddresses = new address[](2);

        vm.expectRevert(IVault.Vault_InvalidConstructorData.selector);
        new Vault(selectors, logicAddresses, address(0));

        // Not sorted selectors array
        bytes4[] memory selectors2 = new bytes4[](3);
        address[] memory logicAddresses2 = new address[](3);
        selectors2[0] = bytes4(uint32(5));
        selectors2[1] = bytes4(uint32(4));
        selectors2[2] = bytes4(uint32(10));
        vm.expectRevert(IVault.Vault_InvalidConstructorData.selector);
        new Vault(selectors2, logicAddresses2, address(0));

        // multiple identical selectors in an array
        selectors2[0] = bytes4(uint32(5));
        selectors2[1] = bytes4(uint32(4));
        selectors2[2] = bytes4(uint32(5));
        vm.expectRevert(IVault.Vault_InvalidConstructorData.selector);
        new Vault(selectors2, logicAddresses2, address(0));

        selectors2[0] = bytes4(uint32(1));
        selectors2[1] = bytes4(uint32(1));
        selectors2[2] = bytes4(uint32(5));
        vm.expectRevert(IVault.Vault_InvalidConstructorData.selector);
        new Vault(selectors2, logicAddresses2, address(0));
    }

    function test_binarySearch() external {
        // array length not equal
        bytes4[] memory selectors = new bytes4[](10);
        address[] memory logicAddresses = new address[](10);
        selectors[0] = bytes4(uint32(1));
        selectors[1] = bytes4(uint32(10));
        selectors[2] = bytes4(uint32(100));
        selectors[3] = bytes4(uint32(1000));
        selectors[4] = bytes4(uint32(10000));
        selectors[5] = bytes4(uint32(100000));
        selectors[6] = bytes4(uint32(1000000));
        selectors[7] = bytes4(uint32(10000000));
        selectors[8] = bytes4(uint32(100000000));
        selectors[9] = bytes4(uint32(1000000000));

        for (uint256 i; i < 10; ++i) {
            logicAddresses[i] = address(uint160(i));
        }

        bytes memory data;
        for (uint256 i; i < 10; ++i) {
            data = abi.encodePacked(data, selectors[i], logicAddresses[i]);
        }

        for (uint256 i; i < 10; ++i) {
            address finded = BinarySearch.binarySearch(
                bytes4(uint32(10 ** i)),
                data
            );
            assertEq(address(uint160(i)), finded);
        }
    }
}
