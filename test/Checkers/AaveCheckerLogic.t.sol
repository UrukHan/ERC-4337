// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AaveCheckerLogic, IAaveCheckerLogic} from "../../src/vault/logics/Checkers/AaveCheckerLogic.sol";
import {AaveActionLogic} from "../../src/vault/logics/OurLogic/AaveActionLogic.sol";
import {AccessControlLogic} from "../../src/vault/logics/AccessControlLogic.sol";
import {BaseContract, Constants} from "../../src/vault/libraries/BaseContract.sol";
import {VaultFactory} from "../../src/VaultFactory.sol";
import {TransferHelper} from "../../src/vault/libraries/utils/TransferHelper.sol";

import {FullDeploy, Registry, VaultProxyAdmin} from "../../script/FullDeploy.s.sol";

contract TimeCheckerLogicTest is Test, FullDeploy {
    bool isTest = true;

    Registry.Contracts reg;

    AaveCheckerLogic vault;

    bytes32 aaveCheckerStoragePointer =
        keccak256("aave checker storage pointer");

    address vaultOwner = makeAddr("VAULT_OWNER");
    address executor = makeAddr("EXECUTOR");

    // mainnet USDC
    address usdcAddress = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    // mainnet WETH
    address wethAddress = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address donor = 0x55CAaBB0d2b704FD0eF8192A7E35D8837e678207; // wallet for token airdrop

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

        vm.prank(vaultOwner);
        vault = AaveCheckerLogic(vaultFactory.deploy(1, 1));

        vm.startPrank(donor);
        IERC20(usdcAddress).transfer(address(vault), 20000 * 1e6);
        IERC20(wethAddress).transfer(address(vault), 10 * 1e18);
        vm.stopPrank();

        vm.startPrank(address(vault));
        vault.aaveCheckerInitialize(
            1.2e18,
            1.5e18,
            address(vault),
            aaveCheckerStoragePointer
        );

        AccessControlLogic(address(vault)).grantRole(
            Constants.EXECUTOR_ROLE,
            executor
        );

        vm.stopPrank();
    }

    function test_aaveChecker_shouldReturnCorrectLocalState() external {
        (
            uint256 lowerHFBoundary,
            uint256 upperHFBoundary,
            address user,
            bool initialized
        ) = vault.getLocalAaveCheckerStorage(aaveCheckerStoragePointer);

        assertEq(lowerHFBoundary, 1.2e18);
        assertEq(upperHFBoundary, 1.5e18);
        assertEq(user, address(vault));
        assertEq(initialized, true);

        (lowerHFBoundary, upperHFBoundary, user, initialized) = vault
            .getLocalAaveCheckerStorage(
                keccak256("not initialized local storage")
            );

        assertEq(lowerHFBoundary, 0);
        assertEq(upperHFBoundary, 0);
        assertEq(user, address(0));
        assertEq(initialized, false);
    }

    function test_aaveChecker_cannotBeInitalizedMultipleTimes() external {
        vm.prank(address(vault));
        vm.expectRevert(
            IAaveCheckerLogic.AaveChecker_AlreadyInitialized.selector
        );
        vault.aaveCheckerInitialize(
            1.1e18,
            1.7e18,
            address(vault),
            aaveCheckerStoragePointer
        );
    }

    function test_aaveChecker_shouldRevertWithWrongBoundaries() external {
        bytes32 storagePointer = keccak256("not initialized local storage");

        vm.prank(address(vault));
        vm.expectRevert(
            IAaveCheckerLogic.AaveChecker_IncorrectHealthFators.selector
        );
        vault.aaveCheckerInitialize(
            0.9e18,
            1.7e18,
            address(vault),
            storagePointer
        );

        vm.prank(address(vault));
        vm.expectRevert(
            IAaveCheckerLogic.AaveChecker_IncorrectHealthFators.selector
        );
        vault.aaveCheckerInitialize(
            1.1e18,
            1.1e18,
            address(vault),
            storagePointer
        );

        vm.prank(address(vault));
        vm.expectRevert(
            IAaveCheckerLogic.AaveChecker_IncorrectHealthFators.selector
        );
        vault.aaveCheckerInitialize(
            1.2e18,
            1.1e18,
            address(vault),
            storagePointer
        );
    }

    function test_aaveChecker_shouldRevertIfNotInitialized() external {
        bytes32 storagePointer = keccak256("not initialized local storage");

        vm.prank(address(vault));
        vm.expectRevert(IAaveCheckerLogic.AaveChecker_NotInitialized.selector);
        vault.checkHF(storagePointer);

        vm.prank(address(vault));
        vm.expectRevert(IAaveCheckerLogic.AaveChecker_NotInitialized.selector);
        vault.setHFBoundaries(1e18, 1.2e18, storagePointer);

        vm.prank(address(vault));
        vm.expectRevert(IAaveCheckerLogic.AaveChecker_NotInitialized.selector);
        vault.getHFBoundaries(storagePointer);
    }

    function test_aaveChecker_setHFBoundaries_shouldChangeBoundaries()
        external
    {
        (uint256 lowerHFBoundary, uint256 upperHFBoundary) = vault
            .getHFBoundaries(aaveCheckerStoragePointer);

        assertEq(lowerHFBoundary, 1.2e18);
        assertEq(upperHFBoundary, 1.5e18);

        vm.prank(vaultOwner);
        vault.setHFBoundaries(1.1e18, 1.2e18, aaveCheckerStoragePointer);

        (lowerHFBoundary, upperHFBoundary) = vault.getHFBoundaries(
            aaveCheckerStoragePointer
        );

        assertEq(lowerHFBoundary, 1.1e18);
        assertEq(upperHFBoundary, 1.2e18);
    }

    function test_aaveChecker_setHFBoundaries_shouldRevertWithWrongBoundaries()
        external
    {
        vm.prank(vaultOwner);
        vm.expectRevert(
            IAaveCheckerLogic.AaveChecker_IncorrectHealthFators.selector
        );
        vault.setHFBoundaries(0.9e18, 1.7e18, aaveCheckerStoragePointer);

        vm.prank(vaultOwner);
        vm.expectRevert(
            IAaveCheckerLogic.AaveChecker_IncorrectHealthFators.selector
        );
        vault.setHFBoundaries(1.1e18, 1.1e18, aaveCheckerStoragePointer);

        vm.prank(vaultOwner);
        vm.expectRevert(
            IAaveCheckerLogic.AaveChecker_IncorrectHealthFators.selector
        );
        vault.setHFBoundaries(1.2e18, 1.1e18, aaveCheckerStoragePointer);
    }

    function test_aaveChecker_setHFBoundaries_accessControl() external {
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.setHFBoundaries(1.1e18, 1.2e18, aaveCheckerStoragePointer);

        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                address(this)
            )
        );
        vault.setHFBoundaries(1.1e18, 1.2e18, aaveCheckerStoragePointer);
    }

    function test_aaveChecker_checkHF_shouldReturnTrue() external {
        uint256 currentHF = reg.lens.aaveLogicLens.getCurrentHF(address(vault));
        assertEq(currentHF, type(uint256).max);
        assertTrue(vault.checkHF(aaveCheckerStoragePointer));
    }

    function test_aaveChecker_checkHF_shouldReturnFalse() external {
        vm.prank(address(vault));
        vault.aaveCheckerInitialize(
            1e18,
            100e18,
            address(vault),
            keccak256("test pointer")
        );

        vm.prank(address(vault));
        AaveActionLogic(address(vault)).supplyAaveAction(wethAddress, 1 ether);

        vm.prank(address(vault));
        AaveActionLogic(address(vault)).borrowAaveAction(usdcAddress, 600e6);

        assertFalse(vault.checkHF(keccak256("test pointer")));
    }
}
