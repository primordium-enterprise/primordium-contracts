// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

library Math512 {

    /**
     * @notice Calculates the 512 bit multiplication of x and y, splitting the result into two uint256 values that hold
     * the least significant bits and the most significant bits, respectively.
     * @dev Original credit to Remco Bloemen under MIT license (https://xn--2-umb.com/17/full-mul/)
     */
    function mul512(uint256 x, uint256 y) internal pure returns (uint256 r0, uint256 r1) {
        assembly {
            let mm := mulmod(x, y, not(0))
            r0 := mul(x, y)
            r1 := sub(sub(mm, r0), lt(mm, r0))
        }
    }

    /**
     * @notice Compares the 512 bit products, and returns true if x1 * y1 < x2 * y2
     */
    function mul512_lt(uint256 x1, uint256 y1, uint256 x2, uint256 y2) internal pure returns (bool) {
        (uint L1, uint G1) = mul512(x1, y1);
        (uint L2, uint G2) = mul512(x2, y2);
        return (
            // If equal most significant bits, but product1 least significant bits are less, return true
            G1 == G2 && L1 < L2 ||
            // Or if product1 most significant bits are less, return true
            G1 < G2
        );
    }

}