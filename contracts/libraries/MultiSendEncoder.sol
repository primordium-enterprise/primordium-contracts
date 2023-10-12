// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.4;

import {console} from "hardhat/console.sol";
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
    ) internal view returns (
        address to,
        uint256 value,
        bytes memory data
    ) {

        uint256 itemsLength = targets.length;

        if (itemsLength == 0) revert IArrayLengthErrors.MissingArrayItems();
        if (
            targets.length != values.length || targets.length != calldatas.length
        ) revert IArrayLengthErrors.MismatchingArrayLengths();

        if (itemsLength > 1) {
            to = executor;
            value = 0;
            uint256 dataLength;
            uint256 i;
            unchecked {
                // Add the predictable data length
                // (1 operation byte + 20 address bytes + 32 value bytes + 32 data length bytes) = 85 bytes
                dataLength += 85 * itemsLength;
                for (; i < itemsLength; ++i) {
                    // Can be unchecked, enough memory bytes to overflow would exceed transaction gas limits first
                    dataLength += calldatas[i].length;
                }
                // Pad data length in bytes to be a multiple of 32 byte words
                // dataLength = ( (dataLength + 31) % 32 ) * 32;
            }
            console.log(dataLength);
            /* solhint-disable no-inline-assembly */
            /// @solidity memory-safe-assembly
            assembly {
                /**
                 * Allocate enough memory for "data", total length =
                 * 32 bytes for data length +
                 * 4 byte multiSend(bytes) selector +
                 * 32 bytes for the abi encoded param offset +
                 * 32 bytes for the dataLength +
                 * dataLength bytes + padding right to make it a multiple of 32
                 */
                data := mload(0x40)
                mstore(0x40, add(0x44, add(data, dataLength)))
                // Store the data length (with the extra 4 bytes for the selector)
                mstore(data, add(dataLength, 0x04))
                // Store the function selector
                mstore(add(data, 0x20), hex"8d80ff0a")
                // Begin allocating the data
                // i is byte index of the data
                i := 0
                // j is the array item index (starting at 1 to skip the array length)
                let j := 0
                for {} lt(j, itemsLength) {} {
                    // Current data offset (data address + 4 selector bytes + 32 data length bytes + i bytes)
                    let currentDataOffset := add(i, add(data, 0x24))
                    // Array item offset is ( j + 1 ) * 32 bytes, the plus one skips the array length
                    let arrayItemOffset := mul(0x20, add(j, 0x01))
                    // Store operation (uint8(0)) and address at once by shifting the address left 11 bytes (88 bits)
                    mstore(currentDataOffset, shl(0x58, mload(add(targets, arrayItemOffset))))
                    // value stores at 21 byte offset
                    mstore(add(currentDataOffset, 0x15), mload(add(values, arrayItemOffset)))
                    // calldata length stores at 53 byte offset
                    let pCalldata := mload(add(calldatas, mul(j, 0x20)))
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
                    // increment the array item index
                    j := add(j, 0x01)
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