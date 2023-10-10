// SPDX-License-Identifier: LGPL-3.0-only
// Primordium Contracts
// Based on Safe Contracts (MultiSendCallOnly.sol)

pragma solidity ^0.8.4;

import {Enum} from "contracts/common/Enum.sol";
import {ExecutorBaseCallOnly} from "./ExecutorBaseCallOnly.sol";

/**
 * LICENSE
 *
 * MultiSendCallOnly.sol is a modified version of Safe's (formerly Gnosis Safe) MultiSendCallOnly.sol
 * https://github.com/safe-global/safe-contracts/blob/main/contracts/libraries/MultiSendCallOnly.sol
 *
 * Originally authored by Stefan George (@Georgi87) and Richard Meissner (@rmeissner).
 *
 * Modifications made by Ben Jett (@BCJdevelopment) include:
 * - Inherits ExecutorBaseCallOnly and includes a modifier ensuring only the Executor can call this function on itself.
 * - The multiSend() function is also changed from public to external visibility.
 * - This contract is made abstract as it is not intended to be deployed on its own.
 * - For successful calls, the MultiSendCallExecuted event is emitted to log each operation.
 */

/**
 * @title Multi Send Call Only - Allows to batch multiple transactions into one, but only calls
 * @notice The guard logic is not required here as this contract doesn't support nested delegate calls
 * @author Stefan George - @Georgi87
 * @author Richard Meissner - @rmeissner
 *
 * Additional Modifications:
 * @author Ben Jett - @BCJdevelopment
 */
abstract contract MultiSendCallOnly is ExecutorBaseCallOnly {

    // event MultiSendCallExecuted(
    //     address indexed target,
    //     uint256 value,
    //     bytes data
    // );

    // constructor() {
    //     // We check to make sure the hash of the CallExecuted event signature has not changed
    //     require(
    //         MultiSendCallExecuted.selector == 0x6e39a901e1305f4f6a54eec2b50de611aa5a49552f9c2b26d577a27a00aa8792,
    //         "MultiSendCallExecuted.selector doesn't match the hash used in multiSend()"
    //     );
    // }
    /**
     * @dev Sends multiple transactions and reverts all if one fails.
     * @param transactions Encoded transactions. Each transaction is encoded as a packed bytes of
     *                     operation has to be uint8(0) in this version (=> 1 byte),
     *                     to as a address (=> 20 bytes),
     *                     value as a uint256 (=> 32 bytes),
     *                     data length as a uint256 (=> 32 bytes),
     *                     data as bytes.
     *                     see abi.encodePacked for more information on packed encoding
     * @notice The code is for most part the same as the normal MultiSend (to keep compatibility),
     *         but reverts if a transaction tries to use a delegatecall.
     * @notice This method is payable as delegatecalls keep the msg.value from the previous call
     *         If the calling method (e.g. execTransaction) received ETH this would revert otherwise
     */
    function multiSend(bytes calldata transactions) external payable onlyExecutor {
        /* solhint-disable no-inline-assembly */
        uint256 operation;
        address to;
        uint256 value;
        bytes calldata data;

        uint256 i = 0;
        while (i < transactions.length) {
            /// @solidity memory-safe-assembly
            assembly {
                // First byte of the data is the operation.
                // We shift right by 248 bits (256 - 8 [operation byte]) since it will always load 32 bytes (a word).
                // This will also zero out unused data.
                operation := shr(0xf8, calldataload(add(transactions.offset, i)))
                // We offset the load address by 1 byte (operation byte)
                // We shift it right by 96 bits (256 - 160 [20 address bytes]) to right-align the data and zero out unused data.
                to := shr(0x60, calldataload(add(transactions.offset, add(i, 0x01))))
                // We offset the load address by 21 byte (operation byte + 20 address bytes)
                value := calldataload(add(transactions.offset, add(i, 0x15)))
                // We offset the load address by 53 byte (operation byte + 20 address bytes + 32 value bytes)
                data.length := calldataload(add(transactions.offset, add(i, 0x35)))
                // The data.offset should be offset by 85 byte (operation byte + 20 address bytes + 32 value bytes + 32 data length bytes)
                data.offset := add(transactions.offset, add(i, 0x55))
            }
            // Call the execution function
            _execute(to, value, data, Enum.Operation(operation));
            // Increment the position in the transactions
            unchecked {
                // Next entry starts at 85 byte + data length
                i += 85 + data.length;
            }
        }
    }
    /* solhint-enable no-inline-assembly */
}
