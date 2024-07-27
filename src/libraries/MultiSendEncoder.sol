// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {BatchArrayChecker} from "src/utils/BatchArrayChecker.sol";

/**
 * @title Multi Send Encoder - A library to encode a multiSend transaction to the executor
 *
 * @author Ben Jett - @benbcjdev
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
    )
        internal
        pure
        returns (address to, uint256 value, bytes memory data)
    {
        BatchArrayChecker.checkArrayLengths(targets.length, values.length, calldatas.length);

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
                }
            }

            assembly ("memory-safe") {
                /**
                 * Allocate enough memory for "data", total length =
                 *  32 bytes for overallDataLength +
                 *  overallDataLength +
                 *  32 bytes buffer space
                 *
                 * overallDataLength =
                 *  4 byte multiSend(bytes) selector +
                 *  32 bytes for the abi encoded param offset +
                 *  32 bytes for the dataLength +
                 *  dataLength bytes + padding right to make it a multiple of 32
                 */
                data := mload(0x40)
                {
                    // Temporarily store the overallDataLength in the scratch space
                    mstore(0, add(0x44, mul(0x20, div(add(dataLength, 0x1f), 0x20))))
                    // Free the memory
                    mstore(0x40, add(data, add(0x40, mload(0))))
                    mstore(data, mload(0))
                }
                // Store the function selector
                mstore(add(data, 0x20), hex"8d80ff0a")
                // Store the abi encoded param offset (function is multiSend(bytes), so offset is 0x20)
                mstore(add(data, 0x24), 0x20)
                // Store the bytes data length
                mstore(add(data, 0x44), dataLength)

                // Begin allocating the data
                // i is byte index of the data
                i := 0
                // j is the array item index
                let j := 0
                for {} lt(i, dataLength) {} {
                    /**
                     * currentDataOffset =
                     *  data address +
                     *  32 bytes overallDataLength +
                     *  4 selector bytes +
                     *  32 bytes for the abi encoded param offset +
                     *  32 data length bytes +
                     *  i bytes
                     */
                    // Store the currentDataOffset in the scratch space 0
                    mstore(0, add(i, add(data, 0x64)))
                    // Array item offset is ( j * 32 bytes ) + 32 bytes to skip the array length
                    // Store array item offset temporarily in scratch space 0x20
                    mstore(0x20, add(0x20, mul(j, 0x20)))
                    // Store operation (uint8(0)) and address at once by shifting the address left 11 bytes (88 bits)
                    mstore(mload(0), shl(0x58, mload(add(targets, mload(0x20)))))
                    // value stores at 21 byte offset
                    mstore(add(mload(0), 0x15), mload(add(values, mload(0x20))))

                    // Store the address of the calldata array item in the scratch space
                    mstore(0x20, mload(add(calldatas, add(0x20, mul(j, 0x20)))))
                    let calldataLength := mload(mload(0x20))
                    // calldata length stores at 53 byte offset
                    mstore(add(mload(0), 0x35), calldataLength)
                    if gt(calldataLength, 0) {
                        // Iterate, storing the data (starting at 85 bytes from the currentDataOffset)
                        let k := 0
                        for {} lt(k, calldataLength) {} {
                            mstore(add(k, add(mload(0), 0x55)), mload(add(k, add(mload(0x20), 0x20))))
                            k := add(k, 0x20)
                        }
                    }
                    // increment the current data index by the static 85 bytes + the length of the calldata
                    i := add(i, add(0x55, calldataLength))
                    // Increment the array item index
                    j := add(j, 0x01)
                }
            }
        } else {
            to = targets[0];
            value = values[0];
            data = calldatas[0];
        }
    }

    /**
     * @dev Encodes the provided targets, values, and calldatas (as calldata parameters) to be executed by the
     * multiSend(bytes) logic.
     *
     * @notice This encodes each transaction as a CALL method (no DELEGATECALLs are used).
     */
    function encodeMultiSendCalldata(
        address executor,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    )
        internal
        pure
        returns (address to, uint256 value, bytes memory data)
    {
        BatchArrayChecker.checkArrayLengths(targets.length, values.length, calldatas.length);

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
                }
            }

            assembly ("memory-safe") {
                /**
                 * Allocate enough memory for "data", total length =
                 *  32 bytes for overallDataLength +
                 *  overallDataLength +
                 *  32 bytes buffer space
                 *
                 * overallDataLength =
                 *  4 byte multiSend(bytes) selector +
                 *  32 bytes for the abi encoded param offset +
                 *  32 bytes for the dataLength +
                 *  dataLength bytes + padding right to make it a multiple of 32
                 */
                data := mload(0x40)
                {
                    // Temporarily store the overallDataLength in the scratch space
                    mstore(0, add(0x44, mul(0x20, div(add(dataLength, 0x1f), 0x20))))
                    // Free the memory
                    mstore(0x40, add(data, add(0x40, mload(0))))
                    mstore(data, mload(0))
                }
                // Store the function selector
                mstore(add(data, 0x20), hex"8d80ff0a")
                // Store the abi encoded param offset (function is multiSend(bytes), so offset is 0x20)
                mstore(add(data, 0x24), 0x20)
                // Store the bytes data length
                mstore(add(data, 0x44), dataLength)

                // Begin allocating the data
                // i is byte index of the data
                i := 0
                // j is the array item index
                let j := 0
                for {} lt(i, dataLength) {} {
                    /**
                     * currentDataOffset =
                     *  data address +
                     *  32 bytes overallDataLength +
                     *  4 selector bytes +
                     *  32 bytes for the abi encoded param offset +
                     *  32 data length bytes +
                     *  i bytes
                     */
                    // Store the currentDataOffset in the scratch space 0
                    mstore(0, add(i, add(data, 0x64)))
                    // Array item offset is j * 32 bytes
                    // Store array item offset temporarily in scratch space 0x20
                    mstore(0x20, mul(j, 0x20))
                    // Store operation (uint8(0)) and address at once by shifting the address left 11 bytes (88 bits)
                    mstore(mload(0), shl(0x58, calldataload(add(targets.offset, mload(0x20)))))
                    // value stores at 21 byte offset
                    mstore(add(mload(0), 0x15), calldataload(add(values.offset, mload(0x20))))

                    // Store the address of the calldata array item in the scratch space
                    mstore(0x20, add(calldatas.offset, calldataload(add(calldatas.offset, mul(j, 0x20)))))
                    let calldataLength := calldataload(mload(0x20))
                    // calldata length stores at 53 byte offset
                    mstore(add(mload(0), 0x35), calldataLength)
                    if gt(calldataLength, 0) {
                        // Iterate, storing the data (starting at 85 bytes from the currentDataOffset)
                        let k := 0
                        for {} lt(k, calldataLength) {} {
                            mstore(add(k, add(mload(0), 0x55)), calldataload(add(k, add(mload(0x20), 0x20))))
                            k := add(k, 0x20)
                        }
                    }
                    // increment the current data index by the static 85 bytes + the length of the calldata
                    i := add(i, add(0x55, calldataLength))
                    // Increment the array item index
                    j := add(j, 0x01)
                }
            }
        } else {
            to = targets[0];
            value = values[0];
            data = calldatas[0];
        }
    }
}
