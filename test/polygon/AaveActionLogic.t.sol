// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ProtocolFees} from "../../src/ProtocolFees.sol";

import {AccessControlLogic} from "../../src/vault/logics/AccessControlLogic.sol";
import {BaseContract, Constants} from "../../src/vault/libraries/BaseContract.sol";

import {ExecutionLogic} from "../../src/vault/logics/ExecutionLogic.sol";
import {VaultFactory} from "../../src/VaultFactory.sol";
import {VaultLogic} from "../../src/vault/logics/VaultLogic.sol";
import {AaveActionLogic, IAaveActionLogic} from "../../src/vault/logics/OurLogic/AaveActionLogic.sol";
import {AaveLogicLib} from "../../src/vault/libraries/AaveLogicLib.sol";

import {TransferHelper} from "../../src/vault/libraries/utils/TransferHelper.sol";

import {FullDeploy, Registry, VaultProxyAdmin} from "../../script/FullDeploy.s.sol";

contract AaveActionLogicTest is Test, FullDeploy {
    bool isTest = true;

    Registry.Contracts reg;

    // mainnet USDC
    address usdcAddress = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    // mainnet WETH
    address wethAddress = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    // wallet for token airdrop
    address donor = 0x55CAaBB0d2b704FD0eF8192A7E35D8837e678207;

    address vault;

    address vaultOwner = makeAddr("VAULT_OWNER");
    address executor = makeAddr("EXECUTOR");
    address user = makeAddr("USER");

    bytes[] multicallData;

    function setUp() external {
        vm.createSelectFork(vm.envString("POL_RPC_URL"));

        vm.startPrank(donor);
        IERC20(usdcAddress).transfer(vaultOwner, 20000e6);
        IERC20(wethAddress).transfer(vaultOwner, 10e18);
        vm.stopPrank();

        reg = deploySystemContracts(
            isTest,
            Registry.contractsByChainId(block.chainid)
        );

        reg.protocolFees = new ProtocolFees(vaultOwner);
        reg.logics.executionLogic = address(
            new ExecutionLogic(reg.protocolFees)
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

        IERC20(wethAddress).approve(vault, type(uint256).max);
        IERC20(usdcAddress).approve(vault, type(uint256).max);

        AccessControlLogic(vault).grantRole(
            Constants.EXECUTOR_ROLE,
            address(executor)
        );

        VaultLogic(vault).depositERC20(wethAddress, 1 ether, vaultOwner);

        vm.stopPrank();
    }

    function test_polygon_aaveActionLogic_supplyAaveAction() external {
        multicallData.push(
            abi.encodeCall(
                IAaveActionLogic.supplyAaveAction,
                (wethAddress, 1 ether)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        assertApproxEqAbs(
            reg.lens.aaveLogicLens.getSupplyAmount(wethAddress, address(vault)),
            1 ether,
            1e2
        );
    }

    function test_polygon_aaveActionLogic_supplyAaveAction_transferFromRevert()
        external
    {
        multicallData.push(
            abi.encodeCall(
                IAaveActionLogic.supplyAaveAction,
                (wethAddress, 2 ether)
            )
        );

        vm.prank(vaultOwner);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        ExecutionLogic(vault).multicall(multicallData);
    }

    function test_polygon_aaveActionLogic_borrowAaveAction() external {
        multicallData.push(
            abi.encodeCall(
                IAaveActionLogic.supplyAaveAction,
                (wethAddress, 1 ether)
            )
        );

        multicallData.push(
            abi.encodeCall(
                IAaveActionLogic.borrowAaveAction,
                (usdcAddress, 1000e6)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        assertApproxEqAbs(
            reg.lens.aaveLogicLens.getSupplyAmount(wethAddress, address(vault)),
            1 ether,
            1e2
        );

        assertEq(
            reg.lens.aaveLogicLens.getCurrentLiquidationThreshold(wethAddress),
            8250
        );

        assertGt(reg.lens.aaveLogicLens.getCurrentHF(address(vault)), 1e18);

        assertApproxEqAbs(
            reg.lens.aaveLogicLens.getTotalDebt(usdcAddress, address(vault)),
            1000e6,
            1e2
        );
    }

    function test_polygon_aaveActionLogic_cannotBorrowMoreThanSupply()
        external
    {
        multicallData.push(
            abi.encodeCall(
                IAaveActionLogic.supplyAaveAction,
                (wethAddress, 1 ether)
            )
        );

        multicallData.push(
            abi.encodeCall(
                IAaveActionLogic.borrowAaveAction,
                (usdcAddress, 10000e6)
            )
        );

        vm.prank(vaultOwner);
        // COLLATERAL_CANNOT_COVER_NEW_BORROW = '36';
        // 'There is not enough collateral to cover a new borrow'
        vm.expectRevert(bytes("36"));
        ExecutionLogic(vault).multicall(multicallData);
    }

    function test_polygon_aaveActionLogic_repayAave() external {
        multicallData.push(
            abi.encodeCall(
                IAaveActionLogic.supplyAaveAction,
                (wethAddress, 1 ether)
            )
        );

        multicallData.push(
            abi.encodeCall(
                IAaveActionLogic.borrowAaveAction,
                (usdcAddress, 1000e6)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        uint256 totalDebt = reg.lens.aaveLogicLens.getTotalDebt(
            usdcAddress,
            address(vault)
        );

        assertApproxEqAbs(totalDebt, 1000e6, 1e2);

        multicallData.pop();
        multicallData[0] = abi.encodeCall(
            IAaveActionLogic.repayAaveAction,
            (usdcAddress, totalDebt)
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        assertEq(
            reg.lens.aaveLogicLens.getTotalDebt(usdcAddress, address(vault)),
            0
        );
    }

    function test_polygon_aaveActionLogic_repayAave_transferFromRevert()
        external
    {
        multicallData.push(
            abi.encodeCall(
                IAaveActionLogic.supplyAaveAction,
                (wethAddress, 1 ether)
            )
        );

        multicallData.push(
            abi.encodeCall(
                IAaveActionLogic.borrowAaveAction,
                (usdcAddress, 1000e6)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        uint256 totalDebt = reg.lens.aaveLogicLens.getTotalDebt(
            usdcAddress,
            address(vault)
        );

        assertApproxEqAbs(totalDebt, 1000e6, 1e2);

        vm.prank(vaultOwner);
        VaultLogic(address(vault)).withdrawTotalERC20(usdcAddress, vaultOwner);

        multicallData.pop();
        multicallData[0] = abi.encodeCall(
            IAaveActionLogic.repayAaveAction,
            (usdcAddress, totalDebt)
        );

        vm.prank(vaultOwner);
        vm.expectRevert(bytes("26"));
        ExecutionLogic(vault).multicall(multicallData);
    }

    function test_polygon_aaveActionLogic_withdrawAave() external {
        multicallData.push(
            abi.encodeCall(
                IAaveActionLogic.supplyAaveAction,
                (wethAddress, 1 ether)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        uint256 totalSupply = reg.lens.aaveLogicLens.getSupplyAmount(
            wethAddress,
            address(vault)
        );

        assertApproxEqAbs(totalSupply, 1 ether, 1e2);

        multicallData[0] = abi.encodeCall(
            IAaveActionLogic.withdrawAaveAction,
            (wethAddress, totalSupply)
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        assertEq(
            reg.lens.aaveLogicLens.getSupplyAmount(wethAddress, address(vault)),
            0
        );
    }

    function test_polygon_aaveActionLogic_revertIfWithdrawMoreThanTotal()
        external
    {
        multicallData.push(
            abi.encodeCall(
                IAaveActionLogic.supplyAaveAction,
                (wethAddress, 1 ether)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        uint256 totalSupply = reg.lens.aaveLogicLens.getSupplyAmount(
            wethAddress,
            address(vault)
        );

        assertApproxEqAbs(totalSupply, 1 ether, 1e2);

        multicallData[0] = abi.encodeCall(
            IAaveActionLogic.withdrawAaveAction,
            (wethAddress, totalSupply + 1)
        );

        vm.prank(vaultOwner);
        // NOT_ENOUGH_AVAILABLE_USER_BALANCE = '32';
        // 'User cannot withdraw more than the available balance'
        vm.expectRevert(bytes("32"));
        ExecutionLogic(vault).multicall(multicallData);
    }

    function test_polygon_aaveActionLogic_cannotWithdrawAllIfDebtExists()
        external
    {
        multicallData.push(
            abi.encodeCall(
                IAaveActionLogic.supplyAaveAction,
                (wethAddress, 1 ether)
            )
        );

        multicallData.push(
            abi.encodeCall(
                IAaveActionLogic.borrowAaveAction,
                (usdcAddress, 1000e6)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        uint256 totalSupply = reg.lens.aaveLogicLens.getSupplyAmount(
            wethAddress,
            address(vault)
        );

        assertApproxEqAbs(totalSupply, 1 ether, 1e2);

        multicallData.pop();
        multicallData[0] = abi.encodeCall(
            IAaveActionLogic.withdrawAaveAction,
            (wethAddress, totalSupply)
        );

        vm.prank(vaultOwner);
        // HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD = '35';
        // 'Health factor is lesser than the liquidation threshold'
        vm.expectRevert(bytes("35"));
        ExecutionLogic(vault).multicall(multicallData);
    }

    function test_polygon_aaveActionLogic_emergencyRepayAave() external {
        multicallData.push(
            abi.encodeCall(
                IAaveActionLogic.supplyAaveAction,
                (wethAddress, 1 ether)
            )
        );

        multicallData.push(
            abi.encodeCall(
                IAaveActionLogic.borrowAaveAction,
                (usdcAddress, 1000e6)
            )
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        assertApproxEqAbs(
            reg.lens.aaveLogicLens.getSupplyAmount(wethAddress, address(vault)),
            1 ether,
            1e2
        );

        assertApproxEqAbs(
            reg.lens.aaveLogicLens.getTotalDebt(usdcAddress, address(vault)),
            1000e6,
            1e2
        );

        vm.roll(block.number + 300);
        vm.warp(block.timestamp + 3000);

        multicallData.pop();
        multicallData[0] = abi.encodeCall(
            IAaveActionLogic.emergencyRepayAave,
            (wethAddress, usdcAddress, 500)
        );

        vm.prank(vaultOwner);
        ExecutionLogic(vault).multicall(multicallData);

        assertGe(
            reg.lens.aaveLogicLens.getSupplyAmount(wethAddress, address(vault)),
            0
        );
        assertEq(
            reg.lens.aaveLogicLens.getTotalDebt(usdcAddress, address(vault)),
            0
        );
    }

    function test_polygon_aaveActionLogic_accessControl() external {
        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        IAaveActionLogic(vault).supplyAaveAction(wethAddress, 1 ether);

        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        IAaveActionLogic(vault).borrowAaveAction(usdcAddress, 1000e6);

        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        IAaveActionLogic(vault).repayAaveAction(usdcAddress, 1000e6);

        vm.prank(vaultOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                vaultOwner
            )
        );
        IAaveActionLogic(vault).repayAaveAction(usdcAddress, 1000e6);

        vm.prank(vaultOwner);
        vm.expectRevert(AaveLogicLib.AaveLogicLib_InitiatorNotValid.selector);
        IAaveActionLogic(vault).executeOperation(
            usdcAddress,
            1000e6,
            0,
            address(vault),
            bytes("")
        );

        vm.prank(user);
        vm.expectRevert(AaveLogicLib.AaveLogicLib_InitiatorNotValid.selector);
        IAaveActionLogic(vault).executeOperation(
            usdcAddress,
            1000e6,
            0,
            address(user),
            bytes("")
        );

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        IAaveActionLogic(vault).supplyAaveAction(wethAddress, 1 ether);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        IAaveActionLogic(vault).borrowAaveAction(usdcAddress, 1000e6);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        IAaveActionLogic(vault).repayAaveAction(usdcAddress, 1000e6);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseContract.UnauthorizedAccount.selector,
                user
            )
        );
        IAaveActionLogic(vault).repayAaveAction(usdcAddress, 1000e6);

        vm.prank(user);
        vm.expectRevert(AaveLogicLib.AaveLogicLib_InitiatorNotValid.selector);
        IAaveActionLogic(vault).executeOperation(
            usdcAddress,
            1000e6,
            0,
            address(vault),
            bytes("")
        );

        vm.prank(user);
        vm.expectRevert(AaveLogicLib.AaveLogicLib_InitiatorNotValid.selector);
        IAaveActionLogic(vault).executeOperation(
            usdcAddress,
            1000e6,
            0,
            address(user),
            bytes("")
        );
    }
}
