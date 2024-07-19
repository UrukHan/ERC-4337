// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

enum ActionModule {
    ADD,
    REMOVE
}

/// @title IVault - Vault interface
/// @notice This interface defines the structure for a Vault contract.
/// @dev It provides function signatures and custom errors to be implemented by a Vault.
interface IVault {
    // =========================
    // Events
    // =========================

    /// @notice Emits when a new module is successfully added to the vault.
    event ModuleAdded(address moduleAddress);

    /// @notice Emits when a module is successfully deleted from the vault.
    event ModuleDeleted(address moduleAddress);

    // =========================
    // Errors
    // =========================

    /// @notice Error to indicate that the function does not exist in the Vault.
    error Vault_FunctionDoesNotExist();

    /// @notice Error to indicate that invalid constructor data was provided.
    error Vault_InvalidConstructorData();

    /// @notice Thrown when attempting to perform an operation on a module that is not listed.
    error Vault_ModuleNotListed(address moduleAddress);

    /// @notice Thrown when attempting to perform an operation on an inactive module.
    error Vault_ModuleIsInactive(address moduleAddress);

    /// @notice Thrown when attempting to add a module that has already been added.
    error Vault_ModuleAlreadyAdded(address moduleAddress);

    /// @notice Thrown when attempting to replace a selector when it's not allowed.
    error Vault_CannotReplaceSelector();

    /// @notice Thrown when attempting to perform an operation on a module that has not been added.
    error Vault_ModuleDoesNotAdded(address moduleAddress);

    // =========================
    // Module control
    // =========================

    /// @notice Adds or removes a module and its selectors.
    /// @param moduleAddress Address to be added or deleted.
    /// @param action Enum indicating the action to be done with the module.
    function moduleAction(address moduleAddress, ActionModule action) external;

    /// @notice Method returning an array of connected modules.
    /// @return Array of module addresses.
    function getModules() external view returns (address[] memory);

    // =========================
    // Main functions
    // =========================

    /// @notice Returns the address of the implementation of the Vault.
    /// @dev This is the address of the contract where the Vault delegates its calls to.
    /// @return implementationAddress The address of the Vault's implementation.
    function getImplementationAddress()
        external
        view
        returns (address implementationAddress);
}
