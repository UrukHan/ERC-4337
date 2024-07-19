// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "forge-std/Test.sol";

import {DittoOracleV3, IDittoOracleV3} from "../../src/DittoOracleV3.sol";
import {Registry} from "../../script/Registry.sol";

contract DittoOracleV3Test is Test {
    Registry.Contracts reg;
    // mainnet USDC
    address usdcAddress = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    // mainnet WETH
    address wethAddress = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;

    address fakeToken = address(12341234);

    uint256 private constant ONE_USDC = 1_000_000;
    uint256 private constant ONE_WETH = 1_000_000_000_000_000_000;

    DittoOracleV3 oracle;

    function setUp() external {
        vm.createSelectFork(vm.envString("POL_RPC_URL"));

        reg = Registry.contractsByChainId(block.chainid);

        oracle = new DittoOracleV3();
        vm.label(usdcAddress, "USDC");
        vm.label(wethAddress, "wETH");
        vm.label(fakeToken, "fake");
    }

    function test_DittoOracleV3_consult() external {
        uint256 usdcWethRate = oracle.consult(
            usdcAddress,
            ONE_USDC,
            wethAddress,
            500,
            address(reg.uniswapFactory)
        );

        uint256 wethUsdcRate = oracle.consult(
            wethAddress,
            ONE_WETH,
            usdcAddress,
            500,
            address(reg.uniswapFactory)
        );
        assertTrue(usdcWethRate > 0);
        assertTrue(wethUsdcRate > 0);
    }

    function test_DittoOracleV3_consult_shouldRevertIfPoolNotFound() external {
        vm.expectRevert(IDittoOracleV3.UniswapOracle_PoolNotFound.selector);
        oracle.consult(
            wethAddress,
            ONE_WETH,
            fakeToken,
            500,
            address(reg.uniswapFactory)
        );
    }
}
