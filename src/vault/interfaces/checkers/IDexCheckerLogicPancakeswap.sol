// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IDexCheckerLogicBase} from "./IDexCheckerLogicBase.sol";

/// @title IDexCheckerLogicPancakeswap - Interface for the DexChecker logic specific to PancakeSwap.
/// @dev This interface extends IDexCheckerLogicBase and provides methods for PancakeSwap specific operations.
interface IDexCheckerLogicPancakeswap is IDexCheckerLogicBase {
    // =========================
    // Initializer
    // =========================

    /// @notice Initializes the DexChecker for PancakeSwap.
    /// @param nftId The ID of the NFT to be associated with the DexChecker.
    /// @param pointer Pointer to the storage location.
    function pancakeswapDexCheckerInitialize(
        uint256 nftId,
        bytes32 pointer
    ) external;

    // =========================
    // Main functions
    // =========================

    /// @notice Checks if the price is out of the allowed tick range on PancakeSwap.
    /// @param pointer Pointer to the storage location.
    /// @return A boolean indicating if the price is out of the tick range.
    function pancakeswapCheckOutOfTickRange(
        bytes32 pointer
    ) external view returns (bool);

    /// @notice Checks if the price is in the allowed tick range on PancakeSwap.
    /// @param pointer Pointer to the storage location.
    /// @return A boolean indicating if the price is in the tick range.
    function pancakeswapCheckInTickRange(
        bytes32 pointer
    ) external view returns (bool);

    /// @notice Checks if fees exist for a given token pair on PancakeSwap.
    /// @param pointer Pointer to the storage location.
    /// @return A boolean indicating if fees exist.
    function pancakeswapCheckFeesExistence(
        bytes32 pointer
    ) external view returns (bool);

    /// @notice Retrieves the local DexChecker storage value for PancakeSwap.
    /// @param pointer Pointer to the storage location.
    /// @return The NFT ID associated with the DexChecker.
    function pancakeswapGetLocalDexCheckerStorage(
        bytes32 pointer
    ) external view returns (uint256);
}
