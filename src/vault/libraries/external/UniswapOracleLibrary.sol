// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/// @title Uniswap Oracle library
/// @notice Provides functions to integrate with V3 pool oracle
library UniswapOracleLibrary {
    // =========================
    // Errors
    // =========================

    /// @dev Thrown when the observation is not initialized
    error ObservationNotInitialized();

    // =========================
    // Methods
    // =========================

    /// @notice Calculates time-weighted means of tick and liquidity for a given Uniswap V3 pool
    /// @param pool Address of the pool that we want to observe
    /// @param secondsAgo Number of seconds in the past from which to calculate the time-weighted means
    /// @return arithmeticMeanTick The arithmetic mean tick from (block.timestamp - secondsAgo) to block.timestamp or block starting tick
    function consult(
        IUniswapV3Pool pool,
        uint32 secondsAgo
    ) internal returns (int24 arithmeticMeanTick) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo;
        secondsAgos[1] = 0;

        try pool.observe(secondsAgos) returns (
            int56[] memory tickCumulatives,
            uint160[] memory secondsPerLiquidityCumulativeX128s
        ) {
            // unused
            secondsPerLiquidityCumulativeX128s;

            arithmeticMeanTick = _calculateArithmeticMeanTick(
                tickCumulatives,
                secondsAgo
            );
        } catch {
            uint16 observationIndex;
            uint16 observationCardinality;

            {
                (, bytes memory data) = address(pool).staticcall(
                    // 0x3850c7bd - selector of "slot0()"
                    abi.encodeWithSelector(0x3850c7bd)
                );
                (
                    ,
                    arithmeticMeanTick,
                    observationIndex,
                    observationCardinality,
                    ,
                    ,

                ) = abi.decode(
                    data,
                    (uint160, int24, uint16, uint16, uint16, uint256, bool)
                );
            }

            if (observationCardinality == 1) {
                pool.increaseObservationCardinalityNext(2);
            } else {
                (uint32 observationTimestamp, int56 tickCumulative, , ) = pool
                    .observations(observationIndex);

                if (observationTimestamp != uint32(block.timestamp)) {
                    return arithmeticMeanTick;
                }

                unchecked {
                    uint256 prevIndex = (uint256(observationIndex) +
                        observationCardinality -
                        1) % observationCardinality;
                    (
                        uint32 prevObservationTimestamp,
                        int56 prevTickCumulative,
                        ,
                        bool prevInitialized
                    ) = pool.observations(prevIndex);

                    if (!prevInitialized) {
                        revert ObservationNotInitialized();
                    }

                    uint32 delta = observationTimestamp -
                        prevObservationTimestamp;
                    arithmeticMeanTick = int24(
                        (tickCumulative - int56(uint56(prevTickCumulative))) /
                            int56(uint56(delta))
                    );
                }
            }
        }
    }

    /// @notice Calculates time-weighted means of tick and liquidity for a given Uniswap V3 pool
    /// @param _pool Address of the pool that we want to observe
    /// @param secondsAgo Number of seconds in the past from which to calculate the time-weighted means
    /// @return arithmeticMeanTick The arithmetic mean tick from (block.timestamp - secondsAgo) to block.timestamp or current tick
    function consultView(
        address _pool,
        uint32 secondsAgo
    ) internal view returns (int24 arithmeticMeanTick) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo;
        secondsAgos[1] = 0;

        IUniswapV3Pool pool = IUniswapV3Pool(_pool);

        try pool.observe(secondsAgos) returns (
            int56[] memory tickCumulatives,
            uint160[] memory secondsPerLiquidityCumulativeX128s
        ) {
            // unused
            secondsPerLiquidityCumulativeX128s;

            arithmeticMeanTick = _calculateArithmeticMeanTick(
                tickCumulatives,
                secondsAgo
            );
        } catch {
            (, bytes memory data) = address(pool).staticcall(
                // 0x3850c7bd - selector of "slot0()"
                abi.encodeWithSelector(0x3850c7bd)
            );
            (, arithmeticMeanTick, , , , , ) = abi.decode(
                data,
                (uint160, int24, uint16, uint16, uint16, uint256, bool)
            );
        }
    }

    // =========================
    // Private functions
    // =========================

    /// @dev calculate the arithmetic mean tick of the pool
    function _calculateArithmeticMeanTick(
        int56[] memory tickCumulatives,
        uint32 secondsAgo
    ) private pure returns (int24 arithmeticMeanTick) {
        unchecked {
            int56 tickCumulativesDelta = tickCumulatives[1] -
                tickCumulatives[0];

            arithmeticMeanTick = int24(
                tickCumulativesDelta / int56(uint56(secondsAgo))
            );

            if (
                tickCumulativesDelta < 0 &&
                (tickCumulativesDelta % int56(uint56(secondsAgo)) != 0)
            ) arithmeticMeanTick--;
        }
    }
}
