// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {Enum} from "src/common/Enum.sol";
import {SelfAuthorized} from "./SelfAuthorized.sol";

/**
 * @title Executor Base - Basic internal execution logic
 *
 * @author Ben Jett @BCJdevelopment
 */
abstract contract ExecutorBase is SelfAuthorized {
    event CallExecuted(address indexed target, uint256 value, bytes data, Enum.Operation operation);

    error CallReverted(bytes reason);

    /**
     * @dev Contract should be able to receive ETH.
     */
    receive() external payable virtual {}

    fallback() external payable virtual {}

    /**
     * @dev Execute an operation's call. This function uses the free memory pointer to store data for event logging,
     * but does not update the pointer. Therefore, if using inline assembly following this method, do not expect the
     * free memory pointer to point to zeroed-out memory.
     */
    function _execute(address target, uint256 value, bytes calldata data, Enum.Operation operation) internal virtual {
        // Copy data to memory (preparing extra space for ABI encoded "CallExecuted" event)
        bytes32 eventDataPointer;
        bytes memory mData;
        uint256 dataLengthPaddedTo32;
        assembly ("memory-safe") {
            // Event data starts at free memory pointer (but do not update)
            eventDataPointer := mload(0x40)
            // Store data starting at 32 value + 32 dataHeader + 32 operation = 96 bytes offset from eventDataPointer
            mData := add(eventDataPointer, 0x60)
            mstore(mData, data.length) // Store data length in bytes

            // Get the data length padded to 32 for ABI encoding the "CallExecuted" event
            dataLengthPaddedTo32 := mul(0x20, div(add(data.length, 0x1f), 0x20))

            // Before copying from calldata, store zero in the last 32 bytes of data to ensure it is padded with zeroes
            // mData + 32 bytes for data length + dataLengthPaddedTo32 - 32 bytes = mData + dataLengthPaddedTo32
            mstore(add(mData, dataLengthPaddedTo32), 0)

            // Copy the data to memory
            calldatacopy(add(mData, 0x20), data.offset, data.length)
        }

        // Run operation, with revert logic
        uint256 success;
        if (operation == Enum.Operation.DelegateCall) {
            assembly ("memory-safe") {
                success := delegatecall(gas(), target, add(mData, 0x20), mload(mData), 0, 0)
            }
        } else {
            assembly ("memory-safe") {
                success := call(gas(), target, value, add(mData, 0x20), mload(mData), 0, 0)
            }
        }

        assembly ("memory-safe") {
            // Revert on error
            if iszero(success) {
                // Store the CallReverted selector with the bytes of return data
                mstore(0, 0x70de1b4b00000000000000000000000000000000000000000000000000000000) // CallReverted
                mstore(0x04, 0x20) // bytes header
                mstore(0x24, returndatasize()) // bytes length
                let returnDataLengthPaddedTo32 := mul(0x20, div(add(returndatasize(), 0x1f), 0x20))
                mstore(add(0x24, returnDataLengthPaddedTo32), 0) // Initialize padding to zero
                returndatacopy(0x44, 0, returndatasize()) // copy return data
                revert(0, add(0x44, returnDataLengthPaddedTo32))
            }

            // Log "CallExecuted" event
            mstore(eventDataPointer, value) // Store value
            mstore(add(eventDataPointer, 0x20), 0x60) // Data header, points past first 3 arguments
            mstore(add(eventDataPointer, 0x40), operation) // Operation
            log2(
                eventDataPointer,
                add(0x80, dataLengthPaddedTo32),
                0x10e1f6f2dc69d266b7ebb871621a2d2b32aaf8a925816195b72993d126606fa8, // CallExecuted selector
                target // target is indexed
            )
        }
    }
}
