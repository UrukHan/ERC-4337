// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IAccount, UserOperation} from "@account-abstraction/contracts/interfaces/IAccount.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {UserOperation, UserOperationLib} from "@account-abstraction/contracts/interfaces/UserOperation.sol";

import {BaseContract} from "../libraries/BaseContract.sol";
import {AccessControlLib} from "../libraries/AccessControlLib.sol";

/// @title IAccountAbstractionLogic - AccountAbstractionLogic interface.
interface IAccountAbstractionLogic is IAccount {
    // =========================
    // Events
    // =========================

    event AA_ExecutionByEntryPoint();

    // =========================
    // Getters
    // =========================

    /// @notice Returns the current entry point used by this account.
    /// @return EntryPoint as an `IEntryPoint` interface.
    /// @dev This function should be implemented by the subclass to return the current entry point used by this account.
    function entryPointAA() external view returns (IEntryPoint);

    /// @inheritdoc IAccount
    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external returns (uint256 validationData);

    /// @notice Gets nonce from th entryPoint contract for this address.
    function getNonceAA() external view returns (uint256);

    /// @notice Check current account deposit in the entryPoint
    function getDepositAA() external view returns (uint256);

    // =========================
    // Main method
    // =========================

    /// @notice Execute data to vault's address via entryPoint
    /// @param data - data for execution
    function executeViaEntryPoint(bytes calldata data) external;

    // =========================
    // Entry point interactions
    // =========================

    /// @notice Deposit more funds for this account in the entryPoint
    function addDepositAA() external payable;

    /// @notice Withdraw value from the account's deposit
    /// @param withdrawAddress target to send to
    /// @param amount to withdraw
    function withdrawDepositToAA(
        address payable withdrawAddress,
        uint256 amount
    ) external;
}
