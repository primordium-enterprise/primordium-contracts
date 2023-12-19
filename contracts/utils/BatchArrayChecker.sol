// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

/**
 * @title A utility library to make it easier to check that the array lengths for a batch method are all equal.
 *
 * @dev Simply provide the array lengths as arguments to the "checkArrayLengths" method, and it will throw an error if
 * the length is zero, or if the lengths do not match.
 */
library BatchArrayChecker {
    error BatchArrayMissingItems();
    error BatchArrayLengthMismatch();

    modifier noZeroLength(uint256 aLength) {
        if (aLength == 0) {
            revert BatchArrayMissingItems();
        }
        _;
    }

    function checkArrayLengths(uint256 aLength, uint256 bLength) internal pure noZeroLength(aLength) {
        if (aLength != bLength) {
            revert BatchArrayLengthMismatch();
        }
    }

    function checkArrayLengths(uint256 aLength, uint256 bLength, uint256 cLength) internal pure noZeroLength(aLength) {
        if (aLength != bLength || aLength != cLength) {
            revert BatchArrayLengthMismatch();
        }
    }

    function checkArrayLengths(
        uint256 aLength,
        uint256 bLength,
        uint256 cLength,
        uint256 dLength
    )
        internal
        pure
        noZeroLength(aLength)
    {
        if (aLength != bLength || aLength != cLength || aLength != dLength) {
            revert BatchArrayLengthMismatch();
        }
    }
}
