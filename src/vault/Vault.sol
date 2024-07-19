// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {SSTORE2} from "./libraries/utils/SSTORE2.sol";
import {BinarySearch} from "./libraries/utils/BinarySearch.sol";

import {IVault, ActionModule} from "./interfaces/IVault.sol";

import {ExtendedEnumerableSet} from "./libraries/external/ExtendedEnumerableSet.sol";
import {BaseContract} from "./libraries/BaseContract.sol";

import {IProtocolModuleList} from "../IProtocolModuleList.sol";

/// @title Vault
/// @notice This contract serves as a proxy for dynamic function execution.
/// @dev It maps function selectors to their corresponding logic contracts.
contract Vault is IVault, BaseContract {
    using ExtendedEnumerableSet for ExtendedEnumerableSet.Set;

    //-----------------------------------------------------------------------//
    // function selectors and logic addresses are stored as bytes data:      //
    // selector . address                                                    //
    // sample:                                                               //
    // 0xaaaaaaaa <- selector                                                //
    // 0xffffffffffffffffffffffffffffffffffffffff <- address                 //
    // 0xaaaaaaaaffffffffffffffffffffffffffffffffffffffff <- one element     //
    //-----------------------------------------------------------------------//

    /// @dev Address where logic and selector bytes are stored using SSTORE2.
    address private immutable logicsAndSelectorsAddress;

    /// @inheritdoc IVault
    address public immutable getImplementationAddress;

    /// @dev Address that stores the list of module addresses and their selectors.
    IProtocolModuleList private immutable _protocolModuleList;

    /// @dev Mapping that stores module addresses according to the selector that belongs to that module.
    mapping(bytes4 functionSelector => address logicAddress)
        private _moduleAddress;
    /// @dev Array of added module addresses.
    ExtendedEnumerableSet.Set private _moduleAddresses;

    /// @notice Initializes a new Vault contract.
    /// @param selectors An array of bytes4 function selectors that correspond
    ///        to the logic addresses.
    /// @param logicAddresses An array of addresses, each being the implementation
    ///        address for the corresponding selector.
    /// @param protocolModuleList Address that stores the list of module addresses and their selectors.
    ///
    /// @dev Sets up the logic and selectors for the Vault contract,
    /// ensuring that the passed selectors are in order and there are no repetitions.
    /// @dev Ensures that the sizes of selectors and logic addresses match.
    /// @dev The constructor uses inline assembly to optimize memory operations and
    /// stores the combined logic and selectors in a specified storage location.
    ///
    /// Requirements:
    /// - `selectors` and `logicAddresses` arrays must have the same length.
    /// - `selectors` array should be sorted in increasing order and have no repeated elements.
    ///
    /// Errors:
    /// - Thrown `Vault_InvalidConstructorData` error if data validation fails.
    constructor(
        bytes4[] memory selectors,
        address[] memory logicAddresses,
        address protocolModuleList
    ) {
        uint256 selectorsLength = selectors.length;

        if (selectorsLength != logicAddresses.length) {
            revert Vault_InvalidConstructorData();
        }

        if (selectorsLength > 0) {
            uint256 length;

            unchecked {
                length = selectorsLength - 1;
            }

            // check that the selectors are sorted and there's no repeating
            for (uint256 i; i < length; ) {
                unchecked {
                    if (selectors[i] >= selectors[i + 1]) {
                        revert Vault_InvalidConstructorData();
                    }

                    ++i;
                }
            }
        }

        bytes memory logicsAndSelectors;

        unchecked {
            logicsAndSelectors = new bytes(selectorsLength * 24);
        }

        assembly ("memory-safe") {
            let logicAndSelectorValue
            // counter
            let i
            // offset in memory to the beginning of selectors array values
            let selectorsOffset := add(selectors, 32)
            // offset in memory to beginning of logicsAddresses array values
            let logicsAddressesOffset := add(logicAddresses, 32)
            // offset in memory to beginning of logicsAndSelectorsOffset bytes
            let logicsAndSelectorsOffset := add(logicsAndSelectors, 32)

            for {

            } lt(i, selectorsLength) {
                // post actions
                i := add(i, 1)
                selectorsOffset := add(selectorsOffset, 32)
                logicsAddressesOffset := add(logicsAddressesOffset, 32)
                logicsAndSelectorsOffset := add(logicsAndSelectorsOffset, 24)
            } {
                // value creation:
                // 0xaaaaaaaaffffffffffffffffffffffffffffffffffffffff0000000000000000
                logicAndSelectorValue := or(
                    mload(selectorsOffset),
                    shl(64, mload(logicsAddressesOffset))
                )
                // store the value in the logicsAndSelectors byte array
                mstore(logicsAndSelectorsOffset, logicAndSelectorValue)
            }
        }

        logicsAndSelectorsAddress = SSTORE2.write(logicsAndSelectors);
        getImplementationAddress = address(this);
        _protocolModuleList = IProtocolModuleList(protocolModuleList);
    }

    // =========================
    // Module control
    // =========================

    /// @inheritdoc IVault
    function moduleAction(
        address moduleAddress,
        ActionModule action
    ) external onlyVaultItself {
        function(address) _add = _addModule;
        function(address) _delete = _deleteModule;

        function(address) _action;

        assembly ("memory-safe") {
            switch action
            case 0 {
                _action := _add
            }
            case 1 {
                _action := _delete
            }
            default {

            }
        }

        _action(moduleAddress);
    }

    /// @inheritdoc IVault
    function getModules() external view returns (address[] memory) {
        return _moduleAddresses.values();
    }

    // =========================
    // Main function
    // =========================

    /// @notice Fallback function to execute logic associated with incoming function selectors.
    /// @dev If a logic for the incoming selector is found, it delegates the call to that logic.
    fallback() external payable {
        address logic = _getAddress(msg.sig);

        if (logic == address(0)) {
            logic = _moduleAddress[msg.sig];

            if (logic == address(0)) {
                revert Vault_FunctionDoesNotExist();
            } else if (_protocolModuleList.isModuleInactive(logic)) {
                revert Vault_ModuleIsInactive(logic);
            }
        }

        assembly ("memory-safe") {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), logic, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    /// @notice Function to accept Native Currency sent to the contract.
    receive() external payable {}

    // =======================
    // Internal functions
    // =======================

    /// @dev Searches for the logic address associated with a function `selector`.
    /// @dev Uses binary search to find the logic address in logicsAndSelectors bytes.
    /// @param selector The function selector.
    /// @return logic The address of the logic contract.
    function _getAddress(
        bytes4 selector
    ) internal view returns (address logic) {
        bytes memory logicsAndSelectors = SSTORE2.read(
            logicsAndSelectorsAddress
        );

        if (logicsAndSelectors.length < 24) {
            revert Vault_FunctionDoesNotExist();
        }

        return BinarySearch.binarySearch(selector, logicsAndSelectors);
    }

    /// @notice Adds a module and its selectors.
    /// @param moduleAddress Address to be added.
    function _addModule(address moduleAddress) internal {
        (bytes memory selectors, bool inactive) = _protocolModuleList
            .getSelectorsByModule(moduleAddress);

        if (selectors.length == 0) {
            revert Vault_ModuleNotListed(moduleAddress);
        }

        if (inactive) {
            revert Vault_ModuleIsInactive(moduleAddress);
        }

        // Not allow to add already existing module
        // revert at the top of method for gas optimization
        if (!_moduleAddresses.add(moduleAddress)) {
            revert Vault_ModuleAlreadyAdded(moduleAddress);
        }

        bytes4 selector;
        uint256 memOffset;
        uint256 length;
        assembly ("memory-safe") {
            memOffset := add(selectors, 32)
            length := div(mload(selectors), 4)
        }

        for (uint256 i; i < length; ) {
            assembly ("memory-safe") {
                i := add(i, 1)
                selector := mload(memOffset)
                memOffset := add(memOffset, 4)
            }

            if (_moduleAddress[selector] == address(0)) {
                _moduleAddress[selector] = moduleAddress;
            } else {
                // attempting to replace an existing method is prohibited
                revert Vault_CannotReplaceSelector();
            }
        }

        emit ModuleAdded(moduleAddress);
    }

    /// @notice Removes a module and its selectors.
    /// @param moduleAddress Address to be deleted
    function _deleteModule(address moduleAddress) internal {
        // Not allow to delete non-existence module
        // revert at the top of method for gas optimization
        if (!_moduleAddresses.remove(moduleAddress)) {
            revert Vault_ModuleDoesNotAdded(moduleAddress);
        }

        (bytes memory selectors, ) = _protocolModuleList.getSelectorsByModule(
            moduleAddress
        );

        bytes4 selector;
        uint256 memOffset;
        uint256 length;
        assembly ("memory-safe") {
            memOffset := add(selectors, 32)
            length := div(mload(selectors), 4)
        }

        for (uint256 i; i < length; ) {
            assembly ("memory-safe") {
                i := add(i, 1)
                selector := mload(memOffset)
                memOffset := add(memOffset, 4)
            }

            if (_moduleAddress[selector] == moduleAddress) {
                _moduleAddress[selector] = address(0);
            } else {
                // attempting to delete an existing or non-existing method is prohibited
                revert Vault_CannotReplaceSelector();
            }
        }

        emit ModuleDeleted(moduleAddress);
    }
}
