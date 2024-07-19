// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {SSTORE2} from "../src/vault/libraries/utils/SSTORE2.sol";

contract SSTORE2Test is Test {
    function test_SSTORE2_shouldCorrectDeployContractWithData() external {
        bytes memory data = hex"010203040506070809101112131415161718";

        address dataContract = SSTORE2.write(data);

        assertEq(dataContract.code.length, 1 + data.length);
        assertEq(dataContract.code, bytes.concat(hex"00", data));
    }

    function test_SSTORE2_shouldCorrectWriteBytecodeData() external {
        bytes memory data = hex"010203040506070809101112131415161718";

        address dataContract = SSTORE2.write(data);

        assertEq(dataContract.code.length, 1 + data.length);
        assertEq(SSTORE2.read(dataContract), data);
    }

    function test_SSTORE2_emptyData() external {
        bytes memory data;

        address dataContract = SSTORE2.write(data);

        assertEq(dataContract.code.length, 1 /* STOP opcode */);
        assertEq(SSTORE2.read(dataContract), data);
    }
}
