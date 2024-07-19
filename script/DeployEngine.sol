// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library DeployEngine {
    function quickSort(
        bytes4[] memory selectors,
        address[] memory logicAddresses
    ) internal pure returns (bytes4[] memory) {
        if (selectors.length <= 1) {
            return selectors;
        }

        int256 low;
        int256 high = int256(selectors.length - 1);
        int256[] memory stack = new int256[](selectors.length);
        int256 top = -1;

        ++top;
        stack[uint(top)] = low;
        ++top;
        stack[uint(top)] = high;

        while (top >= 0) {
            high = stack[uint(top)];
            --top;
            low = stack[uint(top)];
            --top;

            int256 pivotIndex = _partition(
                selectors,
                logicAddresses,
                low,
                high
            );

            if (pivotIndex - 1 > low) {
                ++top;
                stack[uint(top)] = low;
                ++top;
                stack[uint(top)] = pivotIndex - 1;
            }

            if (pivotIndex + 1 < high) {
                ++top;
                stack[uint(top)] = pivotIndex + 1;
                ++top;
                stack[uint(top)] = high;
            }
        }

        return selectors;
    }

    function _partition(
        bytes4[] memory selectors,
        address[] memory logicAddresses,
        int256 low,
        int256 high
    ) internal pure returns (int256) {
        bytes4 pivot = selectors[uint256(high)];
        int256 i = low - 1;

        for (int256 j = low; j < high; ++j) {
            if (selectors[uint256(j)] <= pivot) {
                i++;
                (selectors[uint256(i)], selectors[uint256(j)]) = (
                    selectors[uint256(j)],
                    selectors[uint256(i)]
                );

                if (logicAddresses.length == selectors.length) {
                    (logicAddresses[uint256(i)], logicAddresses[uint256(j)]) = (
                        logicAddresses[uint256(j)],
                        logicAddresses[uint256(i)]
                    );
                }
            }
        }

        (selectors[uint256(i + 1)], selectors[uint256(high)]) = (
            selectors[uint256(high)],
            selectors[uint256(i + 1)]
        );

        if (logicAddresses.length == selectors.length) {
            (logicAddresses[uint256(i + 1)], logicAddresses[uint256(high)]) = (
                logicAddresses[uint256(high)],
                logicAddresses[uint256(i + 1)]
            );
        }

        return i + 1;
    }
}
