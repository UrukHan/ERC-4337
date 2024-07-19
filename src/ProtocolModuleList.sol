// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Ownable} from "./external/Ownable.sol";
import {IProtocolModuleList} from "./IProtocolModuleList.sol";

/// @title ProtocolModuleList
/// @dev Manages the list of modules added to the protocol, their activation status, and associated selectors.
contract ProtocolModuleList is Ownable, IProtocolModuleList {
    // =========================
    // Storage
    // =========================

    /// @dev List of modules added to the protocol.
    mapping(address moduleAddress => Module) private _moduleList;

    // =========================
    // Admin functions
    // =========================

    /// @inheritdoc IProtocolModuleList
    function addModule(
        address moduleAddress,
        bytes4[] calldata selectors
    ) external onlyOwner {
        if (_listedModule(moduleAddress)) {
            revert ProtocolModuleList_ModuleAlreadyExists();
        }

        uint256 selectorsLength = selectors.length;

        if (selectorsLength > 0) {
            uint256 length;

            unchecked {
                length = selectorsLength - 1;
            }

            // check that the selectors are sorted and there's no repeating
            for (uint256 i; i < length; ) {
                unchecked {
                    if (selectors[i] >= selectors[i + 1]) {
                        revert ProtocolModuleList_InvalidSelectorsArray();
                    }

                    ++i;
                }
            }
        }

        bytes memory _selectors;
        unchecked {
            _selectors = new bytes(4 * selectorsLength);
        }

        assembly ("memory-safe") {
            for {
                let selectorsOffset := selectors.offset
                let _selectorsOffset := add(_selectors, 32)
            } selectorsLength {
                selectorsLength := sub(selectorsLength, 1)
                selectorsOffset := add(selectorsOffset, 32)
                _selectorsOffset := add(_selectorsOffset, 4)
            } {
                mstore(_selectorsOffset, calldataload(selectorsOffset))
            }
        }

        _moduleList[moduleAddress].moduleSelectors = _selectors;
    }

    /// @inheritdoc IProtocolModuleList
    function deactivateModule(address moduleAddress) external onlyOwner {
        if (!_listedModule(moduleAddress)) {
            revert ProtocolModuleList_ModuleDoesNotExists();
        }

        _moduleList[moduleAddress].inactive = true;
    }

    /// @inheritdoc IProtocolModuleList
    function activateModule(address moduleAddress) external onlyOwner {
        if (!_listedModule(moduleAddress)) {
            revert ProtocolModuleList_ModuleDoesNotExists();
        }

        _moduleList[moduleAddress].inactive = false;
    }

    // =========================
    // Getters
    // =========================

    /// @inheritdoc IProtocolModuleList
    function listedModule(
        address moduleAddress
    ) external view returns (bool listed) {
        return _listedModule(moduleAddress);
    }

    /// @inheritdoc IProtocolModuleList
    function isModuleInactive(
        address moduleAddress
    ) external view returns (bool inactive) {
        return _moduleList[moduleAddress].inactive;
    }

    /// @inheritdoc IProtocolModuleList
    function getSelectorsByModule(
        address moduleAddress
    ) external view returns (bytes memory selectors, bool inactive) {
        Module storage module = _moduleList[moduleAddress];
        selectors = module.moduleSelectors;
        inactive = module.inactive;
    }

    // =========================
    // Private functions
    // =========================

    /// @dev Checks if a module is listed in the protocol.
    /// @param moduleAddress Address of the module to check.
    /// @return listed True if the module is listed, false otherwise.
    function _listedModule(
        address moduleAddress
    ) private view returns (bool listed) {
        assembly ("memory-safe") {
            mstore(0, moduleAddress)
            mstore(32, _moduleList.slot)

            // bytes array length > 0
            listed := gt(sload(keccak256(0, 64)), 0)
        }
    }
}
