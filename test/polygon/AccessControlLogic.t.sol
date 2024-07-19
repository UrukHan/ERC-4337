// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {AccessControlLogic, IAccessControlLogic} from "../../src/vault/logics/AccessControlLogic.sol";
import {BaseContract, Constants} from "../../src/vault/libraries/BaseContract.sol";
import {VaultFactory} from "../../src/VaultFactory.sol";
import {Vault} from "../../src/vault/Vault.sol";
import {UpgradeLogic} from "../../src/vault/UpgradeLogic.sol";

import {FullDeploy, DeployEngine, Registry, VaultProxyAdmin} from "../../script/FullDeploy.s.sol";

contract TestLogic is AccessControlLogic {
    function initOnlyOwnerOrVaultItself()
        external
        view
        onlyOwnerOrVaultItself
        returns (bool)
    {
        return true;
    }

    function initOnlyRoleOrOwner()
        external
        view
        onlyRoleOrOwner(Constants.EXECUTOR_ROLE)
        returns (bool)
    {
        return true;
    }
}

contract AccessControlTest is Test, FullDeploy {
    bool isTest = true;

    VaultFactory vaultFactory;
    VaultProxyAdmin vaultProxyAdmin;
    TestLogic vault;
    address vaultOwner;
    uint256 vaultOwnerPk;
    address executor = makeAddr("EXECUTOR");
    address user = makeAddr("USER");

    function setUp() external {
        (vaultOwner, vaultOwnerPk) = makeAddrAndKey("VAULT_OWNER");
        vm.createSelectFork(vm.envString("POL_RPC_URL"));

        TestLogic testLogic = new TestLogic();

        Registry.Contracts memory reg = deploySystemContracts(
            isTest,
            Registry.contractsByChainId(block.chainid)
        );
        (bytes4[] memory selectors, address[] memory logicAddresses) = _getData(
            reg.logics
        );
        bytes4[] memory _selectors = new bytes4[](selectors.length + 2);
        address[] memory _logicAddresses = new address[](selectors.length + 2);

        uint256 i;
        for (; i < selectors.length; ++i) {
            _selectors[i] = selectors[i];
            _logicAddresses[i] = logicAddresses[i];
        }
        _selectors[i] = TestLogic.initOnlyOwnerOrVaultItself.selector;
        _selectors[i + 1] = TestLogic.initOnlyRoleOrOwner.selector;
        _logicAddresses[i] = address(testLogic);
        _logicAddresses[i + 1] = address(testLogic);

        DeployEngine.quickSort(_selectors, _logicAddresses);

        ProxyAdmin proxyAdminFactory = new ProxyAdmin();

        uint256 nonce = vm.getNonce(address(this));
        reg.vaultProxyAdmin = new VaultProxyAdmin(
            vm.computeCreateAddress(address(this), nonce + 2)
        );

        VaultFactory _vaultFactory = new VaultFactory(
            address(reg.logics.vaultUpgradeLogic),
            address(reg.vaultProxyAdmin)
        );

        vaultFactory = VaultFactory(
            address(
                new TransparentUpgradeableProxy(
                    address(_vaultFactory),
                    address(proxyAdminFactory),
                    abi.encodeCall(VaultFactory.initialize, (address(this)))
                )
            )
        );
        Vault _vault = new Vault(_selectors, _logicAddresses, address(0));

        vaultFactory.addNewImplementation(address(_vault));

        vm.prank(vaultOwner);
        address vaultProxy = vaultFactory.deploy(1, 1);

        vault = TestLogic(vaultProxy);
    }

    function test_accessControl_creatorAndId() external {
        (address creator, uint16 vaultId) = vault.creatorAndId();
        assertTrue(creator == vaultOwner);
        assertTrue(vaultId == 1);
    }

    function test_vault_transferOwnership_accessControl() external {
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        AccessControlLogic(address(vault)).transferOwnership(executor);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        AccessControlLogic(address(vault)).transferOwnership(user);
    }

    event OwnershipTransferred(
        address indexed oldOwner,
        address indexed newOwner
    );

    function test_vault_transferOwnership_shouldEmitEvent() external {
        vm.prank(vaultOwner);
        vm.expectEmit();
        emit OwnershipTransferred(vaultOwner, executor);
        AccessControlLogic(address(vault)).transferOwnership(executor);

        address owner = AccessControlLogic(address(vault)).owner();
        assertTrue(owner == executor);
    }

    function test_accessControl_grantRole() external {
        assertFalse(vault.hasRole(Constants.EXECUTOR_ROLE, executor));

        vm.prank(vaultOwner);
        vault.grantRole(Constants.EXECUTOR_ROLE, executor);
        assertTrue(vault.hasRole(Constants.EXECUTOR_ROLE, executor));

        assertFalse(vault.hasRole(Constants.EXECUTOR_ROLE, vaultOwner));
        vm.prank(address(vault));
        vault.grantRole(Constants.EXECUTOR_ROLE, vaultOwner);
        assertTrue(vault.hasRole(Constants.EXECUTOR_ROLE, vaultOwner));
    }

    function test_accessControl_isValidSignature() external {
        bytes32 hash = keccak256("validHash");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(vaultOwnerPk, hash);

        bytes memory sig = new bytes(65);
        assembly {
            mstore(add(sig, 32), r)
            mstore(add(sig, 65), v)
            mstore(add(sig, 64), s)
        }

        assertEq(bytes4(0x1626ba7e), vault.isValidSignature(hash, sig));

        assembly {
            mstore(add(sig, 64), sub(s, 1))
        }
        assertEq(bytes4(0xffffffff), vault.isValidSignature(hash, sig));
    }

    function test_accessControl_grantRole_accessControl() external {
        vm.prank(vaultOwner);
        vault.grantRole(Constants.EXECUTOR_ROLE, executor);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.grantRole(Constants.EXECUTOR_ROLE, executor);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.grantRole(Constants.EXECUTOR_ROLE, user);
    }

    function test_accessControl_revokeRole() external {
        vm.prank(vaultOwner);
        vault.grantRole(Constants.EXECUTOR_ROLE, executor);
        assertTrue(vault.hasRole(Constants.EXECUTOR_ROLE, executor));

        vm.prank(vaultOwner);
        vault.revokeRole(Constants.EXECUTOR_ROLE, executor);
        assertFalse(vault.hasRole(Constants.EXECUTOR_ROLE, executor));
    }

    function test_accessControl_revokeRole_accessControl() external {
        vm.prank(vaultOwner);
        vault.grantRole(Constants.EXECUTOR_ROLE, executor);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.revokeRole(Constants.EXECUTOR_ROLE, executor);
    }

    function test_baseContract_accessControl() external {
        vm.prank(vaultOwner);
        assertTrue(vault.initOnlyRoleOrOwner());

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.initOnlyRoleOrOwner();

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.initOnlyRoleOrOwner();
    }

    function test_baseContract_accessControlRoles() external {
        vm.prank(vaultOwner);
        assertTrue(vault.initOnlyRoleOrOwner());

        vm.prank(vaultOwner);
        vault.grantRole(Constants.EXECUTOR_ROLE, executor);

        vm.prank(executor);
        assertTrue(vault.initOnlyRoleOrOwner());

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.initOnlyRoleOrOwner();
    }
}
