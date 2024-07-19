// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPartnerFeeModule {
    // =========================
    // Errors
    // =========================

    error PartnerFeeModule_PartnerIsNotExists();
    error PartnerFeeModule_FixFeeForTokenAddressNotInstalled();

    // =========================
    // Actions
    // =========================

    function partnerFeeMulticall(
        bytes[] calldata data,
        address tokenAddress
    ) external payable;
}
