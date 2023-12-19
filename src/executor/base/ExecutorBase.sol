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

    bytes32 private immutable CALL_EXECUTED_EVENT_SELECTOR = CallExecuted.selector;

    error CallReverted(bytes reason);

    /**
     * @dev Contract should be able to receive ETH.
     */
    receive() external payable virtual {}

    fallback() external payable virtual {}

    /**
     * @dev Execute an operation's call.
     */
    function _execute(address target, uint256 value, bytes calldata data, Enum.Operation operation) internal virtual {
        // Copy data to memory (preparing extra space for ABI encoded event)
        bytes32 eventDataStart;
        bytes memory dataMemCopy;
        uint256 dataLengthPaddedTo32;
        assembly ("memory-safe") {
            eventDataStart := mload(0x40)
            // Store data starting at 32 value + 32 dataHeader + 32 operation
            dataMemCopy := add(eventDataStart, 0x60)
            mstore(dataMemCopy, data.length)
            calldatacopy(add(dataMemCopy, 0x20), data.offset, data.length)

            // Update free mem pointer, 32 value + 32 dataHeader + 32 operation + 32 dataLength + dataLengthPaddedTo32
            dataLengthPaddedTo32 := mul(0x20, div(add(data.length, 0x1f), 0x20))
            mstore(0x40, add(add(eventDataStart, 0x80), dataLengthPaddedTo32))
        }

        // Run operation, with revert logic
        if (operation == Enum.Operation.DelegateCall) {
            assembly ("memory-safe") {
                if iszero(delegatecall(gas(), target, add(dataMemCopy, 0x20), mload(dataMemCopy), 0, 0)) {
                    let m := mload(0x40)
                    // Store the CallReverted selector with the bytes of return data
                    mstore(m, 0x70de1b4b00000000000000000000000000000000000000000000000000000000) // `CallReverted(bytes)`
                    mstore(add(m, 0x04), 0x20) // bytes header
                    mstore(add(m, 0x24), returndatasize()) // bytes length
                    returndatacopy(add(m, 0x44), 0, returndatasize()) // copy return data
                    revert(
                        m,
                        add(0x44, mul(0x20, div(add(returndatasize(), 0x1f), 0x20))) // pad returndatasize to 32 bytes
                    )
                }
            }
        } else {
            assembly ("memory-safe") {
                if iszero(call(gas(), target, value, add(dataMemCopy, 0x20), mload(dataMemCopy), 0, 0)) {
                    let m := mload(0x40)
                    // Store the CallReverted selector with the bytes of return data
                    mstore(m, 0x70de1b4b00000000000000000000000000000000000000000000000000000000) // `CallReverted(bytes)`
                    mstore(add(m, 0x04), 0x20) // bytes header
                    mstore(add(m, 0x24), returndatasize()) // bytes length
                    returndatacopy(add(m, 0x44), 0, returndatasize()) // copy return data
                    revert(
                        m,
                        add(0x44, mul(0x20, div(add(returndatasize(), 0x1f), 0x20))) // pad returndatasize to 32 bytes
                    )
                }
            }
        }

        // Log the event for successful operation
        bytes32 callExecutedSelector = CALL_EXECUTED_EVENT_SELECTOR;
        assembly ("memory-safe") {
            // Store value
            mstore(eventDataStart, value)
            // Data header, starts after 3 arguments
            mstore(add(eventDataStart, 0x20), 0x60)
            // Operation
            mstore(add(eventDataStart, 0x40), operation)
            // Log
            log2(eventDataStart, add(dataLengthPaddedTo32, 0x80), callExecutedSelector, target)
        }

        // (bool success,) = target.call{value: value}(data);
        // if (!success) revert CallReverted(target, value, data, operation);
        // emit CallExecuted(target, value, data, operation);
    }
}
