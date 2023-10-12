// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.4;

import {IArrayLengthErrors} from "../interfaces/IArrayLengthErrors.sol";

/**
 * @title Multi Send Encoder - A library to encode a multiSend transaction to the executor
 *
 * @author Ben Jett - @BCJdevelopment
 */
library MultiSendEncoder {

    /**
     * @dev Encodes the provided targets, values, and calldatas to be executed by the multiSend(bytes) logic.
     *
     * @notice This encodes each transaction as a CALL method (no DELEGATECALLs are used).
     */
    function encodeMultiSend(
        address executor,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) internal pure returns (
        address to,
        uint256 value,
        bytes memory data
    ) {

        if (targets.length == 0) revert IArrayLengthErrors.MissingArrayItems();
        if (
            targets.length != values.length || targets.length != calldatas.length
        ) revert IArrayLengthErrors.MismatchingArrayLengths();

        if (targets.length > 1) {
            to = executor;
            value = 0;
            uint256 dataLength;
            uint256 i;
            unchecked {
                // Add the predictable data length
                // (1 operation byte + 20 address bytes + 32 value bytes + 32 data length bytes) = 85 bytes
                dataLength += 85 * targets.length;
                for (; i < targets.length; ++i) {
                    // Can be unchecked, enough memory bytes to overflow would exceed transaction gas limits first
                    dataLength += calldatas[i].length;
                    ++i;
                }
                // Set data length to be a multiple of 32 byte words
                dataLength = (dataLength + 31) % 32;
            }
            /* solhint-disable no-inline-assembly */
            /// @solidity memory-safe-assembly
            assembly {
                // Allocate enough memory for "data", plus 4 bytes for the multiSend(bytes) selector
                let p := mload(0x40)
                mstore(0x40, add(0x04, add(add(p, i), dataLength)))
                // Store the function selector
                mstore(p, hex"8d80ff0a")
                // Begin allocating the data
                data := add(p, 0x04)
                mstore(data, dataLength)
                let j := 0x20
                i := 0
                // We store each transaction in a packed format, so must shift left as needed
                for {} lt(i, dataLength) {
                    j := add(j, 0x20)
                } {
                    let currentDataOffset := add(i, add(data, 0x20))
                    // Store operation (uint8(0)) and address at once by shifting the address left 11 bytes (88 bits)
                    mstore(currentDataOffset, shl(0x58, mload(add(targets, j))))
                    // value stores at 21 byte offset
                    mstore(add(currentDataOffset, 0x15), mload(add(values, j)))
                    // calldata length stores at 53 byte offset
                    let pCalldata := mload(add(calldatas, j))
                    let calldataLength := mload(pCalldata)
                    mstore(add(currentDataOffset, 0x35), calldataLength)
                    if gt(calldataLength, 0) {
                        // Iterate, storing the data (starting at 85 bytes from the currentDataOffset)
                        let k := 0
                        for {} lt(k, calldataLength) {
                            k := add(k, 0x20)
                        } {
                            mstore(add(k, add(currentDataOffset, 0x55)), mload(add(k, add(pCalldata, 0x20))))
                        }
                    }
                    // increment the current data index by the static 85 bytes + the length of the calldata
                    i := add(i, add(0x55, calldataLength))
                }
            }
            /* solhint-enable no-inline-assembly */
        } else {
            to = targets[0];
            value = values[0];
            data = calldatas[0];
        }

    }

}