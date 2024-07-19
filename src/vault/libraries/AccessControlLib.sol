// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/// @title AccessControlLib
/// @notice A library for managing access controls with roles and ownership.
/// @dev Provides the structures and functions needed to manage roles and determine ownership.
library AccessControlLib {
    using ECDSA for bytes32;

    // =========================
    // Errors
    // =========================

    /// @notice Thrown when attempting to initialize an already initialized vault.
    error AccessControlLib_AlreadyInitialized();

    // =========================
    // Storage
    // =========================

    // bytes4(keccak256("isValidSignature(bytes32,bytes)")
    bytes4 internal constant EIP1271_MAGIC_VALUE = 0x1626ba7e;

    /// @dev Storage position for the access control struct, to avoid collisions in storage.
    /// @dev Uses the "magic" constant to find a unique storage slot.
    bytes32 constant ROLES_STORAGE_POSITION = keccak256("vault.roles.storage");

    /// @notice Struct to store roles and ownership details.
    struct RolesStorage {
        // Role-based access mapping
        mapping(bytes32 role => mapping(address account => bool)) roles;
        // Address that created the entity
        address creator;
        // Identifier for the vault
        uint16 vaultId;
        // Flag to decide if cross chain logic is not allowed
        bool crossChainLogicInactive;
        // Owner address
        address owner;
        // Flag to decide if `owner` or `creator` is used
        bool useOwner;
    }

    // =========================
    // Main library logic
    // =========================

    /// @dev Retrieve the storage location for roles.
    /// @return s Reference to the roles storage struct in the storage.
    function rolesStorage() internal pure returns (RolesStorage storage s) {
        bytes32 position = ROLES_STORAGE_POSITION;
        assembly ("memory-safe") {
            s.slot := position
        }
    }

    /// @dev Fetch the owner of the vault.
    /// @dev Determines whether to use the `creator` or the `owner` based on the `useOwner` flag.
    /// @return Address of the owner.
    function getOwner() internal view returns (address) {
        AccessControlLib.RolesStorage storage s = AccessControlLib
            .rolesStorage();

        if (s.useOwner) {
            return s.owner;
        } else {
            return s.creator;
        }
    }

    /// @dev If this smart-contract is an owner of other contract - this contract must implement ERC1271 method.
    ///      In case of multisig, signature can be several concatenated signatures
    ///      If owner is EOA, perform a regular ecrecover.
    /// @param dataHash 32 bytes hash of the data signed
    /// @param signature Signature byte array associated with dataHash
    /// @return isValidSig bool value.
    function isValidSignature(
        bytes32 dataHash,
        bytes calldata signature
    ) internal view returns (bool isValidSig) {
        address owner = AccessControlLib.getOwner();

        bytes32 _dataHash = dataHash.toEthSignedMessageHash();

        // first try to recover EthSignedMessageHash
        address retAddress = _dataHash.recover(signature);

        if (retAddress != owner) {
            // then, if not valid - just a dataHash
            retAddress = dataHash.recover(signature);
        }

        isValidSig = retAddress == owner;

        if (!isValidSig) {
            bytes4 eip1271Value;

            // first try to recover EthSignedMessageHash
            assembly ("memory-safe") {
                let ptr := mload(64)
                let sigLen := signature.length

                // isValidSignature selector
                mstore(ptr, 0x1626ba7e)
                mstore(add(ptr, 32), _dataHash)
                mstore(add(ptr, 64), 64)
                mstore(add(ptr, 96), sigLen)
                calldatacopy(add(ptr, 128), signature.offset, sigLen)

                // pop - the reason for failure does not matter, validation is performed in another way
                pop(
                    staticcall(
                        gas(),
                        owner,
                        add(ptr, 28),
                        add(100, sigLen),
                        0,
                        0
                    )
                )

                returndatacopy(0, 0, returndatasize())

                // if returndatasize < 32 or returndatasize > 32 -> return empty value
                if or(lt(returndatasize(), 32), gt(returndatasize(), 32)) {
                    mstore(0, 0)
                }

                eip1271Value := mload(0)
            }

            if (eip1271Value == bytes4(0)) {
                return false;
            }

            if (eip1271Value != EIP1271_MAGIC_VALUE) {
                // then, if not valid - just a dataHash
                // if returndatasize == 32 -> owner is contract and we can call directly
                eip1271Value = IERC1271(owner).isValidSignature(
                    dataHash,
                    signature
                );
            }

            isValidSig = eip1271Value == EIP1271_MAGIC_VALUE;
        }
    }

    /// @dev Returns the address of the creator of the vault and its ID.
    /// @return The creator's address and the vault ID.
    function getCreatorAndId() internal view returns (address, uint16) {
        AccessControlLib.RolesStorage storage s = AccessControlLib
            .rolesStorage();
        return (s.creator, s.vaultId);
    }

    /// @dev Initializes the `creator` and `vaultId` for a new vault.
    /// @dev Should only be used once. Reverts if already set.
    /// @param creator Address of the vault creator.
    /// @param vaultId Identifier for the vault.
    function initializeCreatorAndId(address creator, uint16 vaultId) internal {
        AccessControlLib.RolesStorage storage s = AccessControlLib
            .rolesStorage();

        // check if vault never existed before
        if (s.vaultId != 0) {
            revert AccessControlLib_AlreadyInitialized();
        }

        s.creator = creator;
        s.vaultId = vaultId;
    }

    /// @dev Fetches cross chain logic flag.
    /// @return True if cross chain logic is active.
    function crossChainLogicIsActive() internal view returns (bool) {
        AccessControlLib.RolesStorage storage s = AccessControlLib
            .rolesStorage();

        return !s.crossChainLogicInactive;
    }
}
