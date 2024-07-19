// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title IEventsAndErrors
/// @dev This contract provides functions for adding automation workflows,
/// interacting with Gelato logic,activating and deactivating vaults
/// and workflows and checking vault status.
interface IEventsAndErrors {
    // =========================
    // Events
    // =========================

    /// @notice Emits when tokens are borrowed from Aave.
    /// @param token The token that was borrowed.
    /// @param amount The amount of tokens borrowed.
    event AaveBorrow(address token, uint256 amount);

    /// @notice Emits when tokens are supplied to Aave.
    /// @param token The token that was supplied.
    /// @param amount The amount of tokens supplied.
    event AaveSupply(address token, uint256 amount);

    /// @notice Emits when a loan is repaid to Aave.
    /// @param token The token that was repaid.
    /// @param amount The amount of tokens repaid.
    event AaveRepay(address token, uint256 amount);

    /// @notice Emits when tokens are withdrawn from Aave.
    /// @param token The token that was withdrawn.
    /// @param amount The amount of tokens withdrawn.
    event AaveWithdraw(address token, uint256 amount);

    /// @notice Emits when an emergency repayment is made using Aave's flash loan mechanism.
    /// @param supplyToken The token used to repay the debt.
    /// @param debtToken The token that was in debt.
    event AaveEmergencyRepay(address supplyToken, address debtToken);

    /// @notice Emits when a Aave's flash loan is executed.
    event AaveFlashLoan();

    /// @notice Emits when a transfer is successfully executed.
    /// @param token The address of the token (address(0) for native currency).
    /// @param from The address of the sender.
    /// @param to The address of the recipient.
    /// @param value The number of tokens (or native currency) transferred.
    event TransferHelperTransfer(
        address indexed token,
        address indexed from,
        address indexed to,
        uint256 value
    );

    /// @notice Emits when ditto fee is transferred.
    /// @param dittoFee The amount of Ditto fee transferred.
    event DittoFeeTransfer(uint256 dittoFee);

    // =========================
    // Errors
    // =========================

    /// @notice Thrown when the initiator of the flashLoan Aave operation
    /// is not valid or authorized.
    error AaveLogicLib_InitiatorNotValid();

    /// @notice Thrown when attempting to initialize an already initialized vault.
    error AccessControlLib_AlreadyInitialized();

    /// @notice Thrown when an account is not authorized to perform a specific action.
    error UnauthorizedAccount(address account);

    /// @notice Thrown when MEV check detects a deviation of price too high.
    error MEVCheck_DeviationOfPriceTooHigh();

    /// @notice Thrown when zero number of tokens are attempted to be added.
    error DexLogicLib_ZeroNumberOfTokensCannotBeAdded();

    /// @notice Thrown when there are not enough token balances on the vault.LiquidityAmounts
    error DexLogicLib_NotEnoughTokenBalances();

    error SSTORE2_DeploymentFailed();

    /// @notice Thrown when `safeTransferFrom` fails.
    error TransferHelper_SafeTransferFromError();

    /// @notice Thrown when `safeTransfer` fails.
    error TransferHelper_SafeTransferError();

    /// @notice Thrown when `safeApprove` fails.
    error TransferHelper_SafeApproveError();

    /// @notice Thrown when `safeGetBalance` fails.
    error TransferHelper_SafeGetBalanceError();

    /// @notice Thrown when `safeTransferNative` fails.
    error TransferHelper_SafeTransferNativeError();
}
