// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

library BasisPoints {
    uint256 internal constant MAX_BPS = 10_000;

    error BPSValueTooLarge(uint256 bpsValue);

    /**
     * @dev Calculates the basis using the provided bpsValue and baseValue. Checks that the bpsValue is no greater than
     * 10_000 (max BPS). Also allows the native solidity overflow checks.
     */
    function bps(uint256 baseValue, uint256 bpsValue) internal pure returns (uint256 basis) {
        if (bpsValue > MAX_BPS) revert BPSValueTooLarge(bpsValue);
        basis = Math.mulDiv(baseValue, bpsValue, MAX_BPS);
    }

    /**
     * @dev Calculates the basis using the provided bpsValue and baseValue, but in an unchecked block to save gas.
     * Therefore, be sure that no overflow is expected to occur if you use this function!
     */
    function bpsUnchecked(uint256 baseValue, uint256 bpsValue) internal pure returns (uint256 basis) {
        unchecked {
            basis = baseValue * bpsValue / MAX_BPS;
        }
    }

    /**
     * @dev Calculates the mulmod(baseValue, bpsValue, MAX_BPS).
     */
    function bpsMulmod(uint256 baseValue, uint256 bpsValue) internal pure returns (uint256 result) {
        result = mulmod(baseValue, bpsValue, MAX_BPS);
    }

    /**
     * @dev Checks that the BPS value is not greater than 10,000, and returns as a uint16.
     */
    function toBps(uint256 bpsValue) internal pure returns (uint16 result) {
        if (bpsValue > MAX_BPS) {
            revert BPSValueTooLarge(bpsValue);
        }

        result = uint16(bpsValue);
    }
}
