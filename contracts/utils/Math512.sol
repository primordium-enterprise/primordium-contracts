// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

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
    function mul512Lt(uint256 x1, uint256 y1, uint256 x2, uint256 y2) internal pure returns (bool) {
        (uint256 least1, uint256 greatest1) = mul512(x1, y1);
        (uint256 least2, uint256 greatest2) = mul512(x2, y2);
        // forgefmt: disable-next-item
        return (
            // If equal most significant bits, but product1 least significant bits are less, return true
            greatest1 == greatest2 && least1 < least2 ||
            // Or if product1 most significant bits are less, return true
            greatest1 < greatest2
        );
    }
}
