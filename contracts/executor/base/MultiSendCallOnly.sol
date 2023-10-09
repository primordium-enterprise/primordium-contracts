// SPDX-License-Identifier: LGPL-3.0-only
// Primordium Contracts
// Based on Safe Contracts (MultiSendCallOnly.sol)

pragma solidity 0.8.4;

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
 * - Uses "calldata" instead of "memory" for the multiSend() function.
 * - The multiSend() function is also changed from public to external visibility.
 * - This contract is made abstract as it is not intended to be deployed on its own.
 * - For each successful call, the CallExecuted event is logged for easier offchain tracking of multiSend transactions.
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
        /// @solidity memory-safe-assembly
        assembly {
            let length := mload(transactions)
            let i := 0x20
            for {
                // Pre block is not used in "while mode"
            } lt(i, length) {
                // Post block is not used in "while mode"
            } {
                // First byte of the data is the operation.
                // We shift by 248 bits (256 - 8 [operation byte]) it right since mload will always load 32 bytes (a word).
                // This will also zero out unused data.
                let operation := shr(0xf8, mload(add(transactions, i)))
                // We offset the load address by 1 byte (operation byte)
                // We shift it right by 96 bits (256 - 160 [20 address bytes]) to right-align the data and zero out unused data.
                let to := shr(0x60, mload(add(transactions, add(i, 0x01))))
                // We offset the load address by 21 byte (operation byte + 20 address bytes)
                let value := mload(add(transactions, add(i, 0x15)))
                // We offset the load address by 53 byte (operation byte + 20 address bytes + 32 value bytes)
                let dataLength := mload(add(transactions, add(i, 0x35)))
                // We offset the load address by 85 byte (operation byte + 20 address bytes + 32 value bytes + 32 data length bytes)
                let data := add(transactions, add(i, 0x55))
                let success := 0
                switch operation
                case 0 {
                    success := call(gas(), to, value, data, dataLength, 0, 0)
                }
                // This version does not allow delegatecalls
                case 1 {
                    revert(0, 0)
                }
                if eq(success, 0) {
                    let errorLength := returndatasize()
                    returndatacopy(0, 0, errorLength)
                    revert(0, errorLength)
                }
                // Next entry starts at 85 byte + data length
                i := add(i, add(0x55, dataLength))
            }
        }
        /* solhint-enable no-inline-assembly */
    }
}
