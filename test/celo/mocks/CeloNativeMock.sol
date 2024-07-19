// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

contract CeloNativeMock is Test {
    struct CeloNativeStruct {
        address from;
        address to;
        uint256 value;
    }

    fallback() external payable {
        address from;
        address to;
        uint256 value;

        assembly {
            from := calldataload(0)
            to := calldataload(32)
            value := calldataload(64)
        }

        vm.deal(to, to.balance + value);
        vm.deal(from, from.balance - value);
    }

    receive() external payable {}
}
