// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.4;

import {Enum} from "contracts/common/Enum.sol";
import {ExecutorBaseCallOnly} from "./ExecutorBaseCallOnly.sol";

/**
 * @title Multi Send - Allows modules to batch multiple transactions into a single execution call.
 * @notice This contract follows the same packed multiSend encoding as Safe contracts (for compatibility),
 * https://github.com/safe-global/safe-contracts/blob/main/contracts/libraries/MultiSend.sol
 *
 * @author Ben Jett - @BCJdevelopment
 */
abstract contract MultiSend is ExecutorBaseCallOnly {

    /**
     * @dev Executes multiple transactions, reverting if any one fails. Only callable by the Executor itself.
     * @notice Follows the same encoding as the Safe protocol.
     * @param transactions Encoded transactions. Each transaction is encoded as a packed bytes of:
     *                     "operation" as uint8(0) since this contract is call only (=> 1 byte),
     *                     "to" as an address (=> 20 bytes),
     *                     "value" as a uint256 (=> 32 bytes),
     *                     "data length" as a uint256 (=> 32 bytes),
     *                     "data" as bytes.
     * see abi.encodePacked for more information on packed encoding:
     * https://docs.soliditylang.org/en/v0.8.21/abi-spec.html#non-standard-packed-mode
     */
    function multiSend(bytes calldata transactions) external onlyExecutor {
        uint256 operation;
        address to;
        uint256 value;
        bytes calldata data;

        uint256 i = 0;
        while (i < transactions.length) {
            /// @solidity memory-safe-assembly
            assembly {
                // First byte of the data is the operation, so use right shift by 31 bytes (248 bits) to get 1 byte.
                operation := shr(0xf8, calldataload(add(transactions.offset, i)))
                // For to, offset the load address by 1 byte, shift right by 12 bytes (96 bits) to get 20 byte address.
                to := shr(0x60, calldataload(add(transactions.offset, add(i, 0x01))))
                // For value, offset the load address by 21 byte (operation byte + 20 address bytes)
                value := calldataload(add(transactions.offset, add(i, 0x15)))
                // To set the data length, offset the load address by 53 byte (21 byte offset + 32 value bytes)
                data.length := calldataload(add(transactions.offset, add(i, 0x35)))
                // To set the start of the data, offset by 85 byte (53 byte offset + 32 data length bytes)
                data.offset := add(transactions.offset, add(i, 0x55))
            }
            // Call the execution function (which will revert if operation is not call only)
            _execute(to, value, data, Enum.Operation(operation));
            // Increment the position in the transactions
            unchecked {
                // Next transaction begins at 85 byte + data length
                i += 0x55 + data.length;
            }
        }
    }
}
