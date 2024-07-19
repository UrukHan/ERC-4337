// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {UserOperation} from "@account-abstraction/contracts/interfaces/IAccount.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {UserOperation, UserOperationLib} from "@account-abstraction/contracts/interfaces/UserOperation.sol";

import {BaseContract} from "../libraries/BaseContract.sol";
import {AccessControlLib} from "../libraries/AccessControlLib.sol";

import {IAccountAbstractionLogic} from "../interfaces/IAccountAbstractionLogic.sol";

/// @title AccountAbstractionLogic - EIP-4337 compatible smart contract wallet.
/// @dev This contract is the base for the Smart Account functionality.
contract AccountAbstractionLogic is IAccountAbstractionLogic, BaseContract {
    using ECDSA for bytes32;

    // AA immutable storage
    IEntryPoint private immutable _entryPoint;

    uint256 private constant SIG_VALIDATION_FAILED = 1;
    uint256 private constant SIG_VALIDATION_SUCCESS = 0;

    /// @dev Constructor that sets the entry point contract.
    /// @param entryPoint_ The address of the entry point contract.
    constructor(address entryPoint_) {
        _entryPoint = IEntryPoint(entryPoint_);
    }

    // =========================
    // Getters
    // =========================

    /// @inheritdoc IAccountAbstractionLogic
    function entryPointAA() external view returns (IEntryPoint) {
        return _entryPoint;
    }

    //// @inheritdoc IAccount
    function validateUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external returns (uint256 validationData) {
        _requireFromEntryPointOrOwner();
        validationData = _validateSignature(userOp, userOpHash);
        _payPrefund(missingAccountFunds);
    }

    /// @inheritdoc IAccountAbstractionLogic
    function getNonceAA() external view returns (uint256) {
        return _entryPoint.getNonce(address(this), 0);
    }

    /// @inheritdoc IAccountAbstractionLogic
    function getDepositAA() external view returns (uint256) {
        return _entryPoint.balanceOf(address(this));
    }

    // =========================
    // Main method
    // =========================

    /// @inheritdoc IAccountAbstractionLogic
    function executeViaEntryPoint(bytes calldata data) external {
        _requireFromEntryPointOrOwner();

        bytes memory _data = data;

        emit AA_ExecutionByEntryPoint();

        assembly ("memory-safe") {
            let success := call(
                gas(),
                address(),
                0, // zero cause this is selfcall
                add(_data, 32),
                mload(_data),
                0,
                0
            )

            returndatacopy(0, 0, returndatasize())

            switch success
            case 1 {
                return(0, returndatasize())
            }
            default {
                revert(0, returndatasize())
            }
        }
    }

    // =========================
    // Entry point interactions
    // =========================

    /// @inheritdoc IAccountAbstractionLogic
    function addDepositAA() external payable {
        _entryPoint.depositTo{value: msg.value}(address(this));
    }

    /// @inheritdoc IAccountAbstractionLogic
    function withdrawDepositToAA(
        address payable withdrawAddress,
        uint256 amount
    ) external onlyVaultItself {
        _entryPoint.withdrawTo(withdrawAddress, amount);
    }

    // =========================
    // Internal functions
    // =========================

    /// @dev Implements the template method of BaseAccount and validates the user's signature for a given operation.
    /// @param userOp The user operation to be validated, provided as a `UserOperation` calldata struct.
    /// @param userOpHash The hashed version of the user operation, provided as a `bytes32` value.
    function _validateSignature(
        UserOperation calldata userOp,
        bytes32 userOpHash
    ) internal view returns (uint256 validationData) {
        return
            AccessControlLib.isValidSignature(userOpHash, userOp.signature)
                ? SIG_VALIDATION_SUCCESS
                : SIG_VALIDATION_FAILED;
    }

    /// @dev This function allows the owner or entry point to execute certain actions.
    /// If the caller is not authorized, the function will revert with an error message.
    /// @notice This modifier is marked as internal and can only be called within the contract itself.
    function _requireFromEntryPointOrOwner() internal view {
        if (msg.sender != address(_entryPoint)) {
            if (msg.sender != AccessControlLib.getOwner()) {
                revert UnauthorizedAccount(msg.sender);
            }
        }
    }

    /// @dev Sends to the EntryPoint (i.e. `msg.sender`) the missing funds for this transaction.
    /// `missingAccountFunds` is the minimum value should send the EntryPoint,
    /// which MAY be zero, in case there is enough deposit, or the userOp has a paymaster.
    function _payPrefund(uint256 missingAccountFunds) internal {
        assembly ("memory-safe") {
            if missingAccountFunds {
                // Ignore failure (it's EntryPoint's job to verify, not the account's).
                pop(call(gas(), caller(), missingAccountFunds, 0, 0, 0, 0))
            }
        }
    }
}
