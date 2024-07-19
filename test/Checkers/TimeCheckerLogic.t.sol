// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {TimeCheckerLogic, ITimeCheckerLogic} from "../../src/vault/logics/Checkers/TimeCheckerLogic.sol";
import {AccessControlLogic} from "../../src/vault/logics/AccessControlLogic.sol";
import {BaseContract, Constants} from "../../src/vault/libraries/BaseContract.sol";
import {VaultFactory} from "../../src/VaultFactory.sol";
import {TransferHelper} from "../../src/vault/libraries/utils/TransferHelper.sol";

import {FullDeploy, Registry, VaultProxyAdmin} from "../../script/FullDeploy.s.sol";

contract TimeCheckerLogicTest is Test, FullDeploy {
    bool isTest = true;

    TimeCheckerLogic vault;

    bytes32 timeCheckerStoragePointer =
        keccak256("time checker storage pointer");

    address vaultOwner = makeAddr("VAULT_OWNER");
    address executor = makeAddr("EXECUTOR");
    address user = makeAddr("USER");

    function setUp() public {
        vm.createSelectFork(vm.envString("POL_RPC_URL"));

        Registry.Contracts memory reg = deploySystemContracts(
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
        vault = TimeCheckerLogic(vaultFactory.deploy(1, 1));

        vm.startPrank(address(vault));
        vault.timeCheckerInitialize(
            uint64(block.timestamp),
            3600,
            timeCheckerStoragePointer
        );

        AccessControlLogic(address(vault)).grantRole(
            Constants.EXECUTOR_ROLE,
            executor
        );

        vm.stopPrank();
    }

    function test_timeChecker_shouldReturnCorrectLocalState() external {
        (uint256 lastActionTime, uint256 timePeriod, bool initialized) = vault
            .getLocalTimeCheckerStorage(timeCheckerStoragePointer);

        assertEq(lastActionTime, block.timestamp);
        assertEq(timePeriod, 3600);
        assertEq(initialized, true);

        (lastActionTime, timePeriod, initialized) = vault
            .getLocalTimeCheckerStorage(
                keccak256("not initialized local storage")
            );

        assertEq(lastActionTime, 0);
        assertEq(timePeriod, 0);
        assertEq(initialized, false);
    }

    function test_timeChecker_cannotBeInitalizedMultipleTimes() external {
        vm.prank(address(vault));
        vm.expectRevert(
            ITimeCheckerLogic.TimeChecker_AlreadyInitialized.selector
        );
        vault.timeCheckerInitialize(0, 0, timeCheckerStoragePointer);
    }

    function test_timeChecker_shouldRevertIfNotInitialized() external {
        bytes32 storagePointer = keccak256("not initialized local storage");

        vm.prank(address(vault));
        vm.expectRevert(ITimeCheckerLogic.TimeChecker_NotInitialized.selector);
        vault.checkTime(storagePointer);

        vm.prank(address(vault));
        vm.expectRevert(ITimeCheckerLogic.TimeChecker_NotInitialized.selector);
        vault.checkTimeView(storagePointer);

        vm.prank(address(vault));
        vm.expectRevert(ITimeCheckerLogic.TimeChecker_NotInitialized.selector);
        vault.setTimePeriod(123, storagePointer);
    }

    function test_timeChecker_checkTime_shouldReturnFalseWithNotEnoughTimePassed()
        external
    {
        vm.prank(address(vault));
        assertFalse(vault.checkTime(timeCheckerStoragePointer));
    }

    function test_timeChecker_checkTime_shouldReturnTrueWithEnoughTimePassed()
        external
    {
        uint256 targetTimestamp = block.timestamp + 3601;
        vm.warp(targetTimestamp);

        vm.prank(address(vault));
        assertTrue(vault.checkTime(timeCheckerStoragePointer));

        (uint256 lastActionTime, , ) = vault.getLocalTimeCheckerStorage(
            timeCheckerStoragePointer
        );
        assertEq(lastActionTime, targetTimestamp);
    }

    function test_timeChecker_checkTime_accessControl() external {
        uint256 targetTimestamp = block.timestamp + 3601;
        vm.warp(targetTimestamp);

        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        vault.checkTime(timeCheckerStoragePointer);

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.checkTime(timeCheckerStoragePointer);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.checkTime(timeCheckerStoragePointer);
    }

    function test_timeChecker_checkTimeView() external {
        (uint256 lastActionTimeBefore, , ) = vault.getLocalTimeCheckerStorage(
            timeCheckerStoragePointer
        );

        vm.warp(block.timestamp + 3601);

        assertTrue(vault.checkTimeView(timeCheckerStoragePointer));

        (uint256 lastActionTimeAfter, , ) = vault.getLocalTimeCheckerStorage(
            timeCheckerStoragePointer
        );

        assertEq(lastActionTimeBefore, lastActionTimeAfter);
    }

    function test_timeChecker_setTimePeriod() external {
        vm.prank(vaultOwner);

        vault.setTimePeriod(121, timeCheckerStoragePointer);

        uint256 targetTimestamp = block.timestamp + 120;

        vm.warp(targetTimestamp);
        vm.prank(address(vault));
        assertFalse(vault.checkTime(timeCheckerStoragePointer));

        targetTimestamp++;
        vm.warp(targetTimestamp);

        vm.prank(address(vault));
        assertTrue(vault.checkTime(timeCheckerStoragePointer));
    }

    function test_timeChecker_setTimePeriod_accessControl() external {
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                executor
            )
        );
        vault.setTimePeriod(121, timeCheckerStoragePointer);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        vault.setTimePeriod(121, timeCheckerStoragePointer);
    }
}
