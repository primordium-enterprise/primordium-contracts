// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

library BasisPoints {

    uint256 internal constant MAX_BPS = 10_000;

    error BPSValueTooLarge(uint256 bpsValue);

    /**
     * Calculates the basis using the provided bpsValue and baseValue. Checks that the bpsValue is no greater than
     * 10_000 (max BPS). Also allows the native solidity overflow checks.
     */
    function bps(uint256 bpsValue, uint256 baseValue) internal pure returns (uint256 basis) {
        if (bpsValue > MAX_BPS) revert BPSValueTooLarge(bpsValue);
        basis = bpsValue * baseValue / MAX_BPS;
    }

    /**
     * Calculates the basis using the provided bpsValue and baseValue, but in an unchecked block to save gas. Therefore,
     * be sure that no overflow is expected to occur if you use this function!
     */
    function bpsUnchecked(uint256 bpsValue, uint256 baseValue) internal pure returns (uint256 basis) {
        unchecked {
            basis = bpsValue * baseValue / MAX_BPS;
        }
    }

}