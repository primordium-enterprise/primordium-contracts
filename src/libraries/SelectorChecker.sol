// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

/**
 * @title SelectorChecker - A gas-optimized library to verify that a list of function signatures match
 * the function selectors for the provided list of calldatas.
 *
 * @author Ben Jett = @BCJdevelopment
 */
library SelectorChecker {
    error InvalidActionSignature(uint256 index);

    /**
     * Checks that the 4 byte selector for each calldata matches the 4 byte selector calculated from the matching
     * function signature (skipping values where the calldata length is zero). Reverts with {InvalidActionSignature}
     * if any of the selectors do not match.
     * @param calldatas The provided calldatas.
     * @param signatures The provided human-readable function signatures. (Example: "transfer(address,uint256)")
     */
    function verifySelectors(bytes[] calldata calldatas, string[] calldata signatures) internal pure {
        bytes4 selector;
        bytes4 signatureHash;

        uint256 i = 0;
        while (i < calldatas.length) {
            if (calldatas[i].length > 0) {
                assembly ("memory-safe") {
                    // Load the function selector from the current calldatas array item
                    selector :=
                        calldataload(
                            add(
                                0x20, // Add an additional 32 bytes offset for the length of the item
                                add(calldatas.offset, calldataload(add(calldatas.offset, mul(i, 0x20))))
                            )
                        )

                    // Store the offset to the signature item in scratch space
                    mstore(0, add(signatures.offset, calldataload(add(signatures.offset, mul(i, 0x20)))))
                    // Check signature length
                    let sigLength := calldataload(mload(0))
                    switch lt(sigLength, 0x20)
                    case 1 {
                        // If less than 32 bytes, just use the scratch space at 0x20
                        calldatacopy(0x20, add(0x20, mload(0)), sigLength)
                        signatureHash := keccak256(0x20, sigLength)
                    }
                    default {
                        let freeMem := mload(0x40)
                        // Free up memory space and copy
                        mstore(0x40, add(freeMem, sigLength))
                        calldatacopy(freeMem, add(0x20, mload(0)), sigLength)
                        signatureHash := keccak256(freeMem, sigLength)
                    }
                }
                if (selector != signatureHash) revert InvalidActionSignature(i);
            } else {
                if (bytes(signatures[i]).length > 0) revert InvalidActionSignature(i);
            }
            unchecked {
                ++i;
            }
        }
    }
}
