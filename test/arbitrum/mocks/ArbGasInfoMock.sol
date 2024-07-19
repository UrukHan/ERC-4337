// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ArbGasInfo} from "../../../src/vault/logics/arbitrumLogics/ArbGasInfo.sol";

/// @title ArbSysMock
/// @notice a mocked version of the Arbitrum system contract, add additional methods as needed
contract ArbGasInfoMock is ArbGasInfo {
    /// @notice Get L1 gas fees paid by the current transaction
    function getCurrentTxL1GasFees() external pure returns (uint256) {
        return 30000000000000;
    }
}
