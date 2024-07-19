// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IPartnerFee} from "./interfaces/IPartnerFee.sol";
import {IPartnerFeeModule} from "./interfaces/IPartnerFeeModule.sol";
import {BaseContract} from "../libraries/BaseContract.sol";
import {MulticallBase} from "../libraries/MulticallBase.sol";

contract PartnerFeeModule is IPartnerFeeModule, BaseContract, MulticallBase {
    IPartnerFee private immutable _partnerFeeContract;

    constructor(address partnerFeeContract) {
        _partnerFeeContract = IPartnerFee(partnerFeeContract);
    }

    // =========================
    // Actions
    // =========================

    function partnerFeeMulticall(
        bytes[] calldata data,
        address tokenAddress
    ) external payable onlyOwnerOrVaultItself {
        uint256 fixFee = _partnerFeeContract.getFixFeesForPartnerByToken(
            tokenAddress
        );

        _multicall(data);

        if (fixFee > 0) {
            IERC20(tokenAddress).transfer(address(_partnerFeeContract), fixFee);
        }
    }
}
