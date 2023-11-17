// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {Enum} from "contracts/common/Enum.sol";
import {IAvatar} from "./IAvatar.sol";

interface ITimelockAvatar is IAvatar {

    enum OperationStatus {
        NoOp, // NoOp when executableAt == 0
        Cancelled, // Cancelled when executableAt == 1
        Done, // Done when executableAt == 2
        Pending, // Pending when executableAt > block.timestamp
        Ready, // Ready when executableAt <= block.timestamp (and not expired)
        Expired // Expired when executableAt + GRACE_PERIOD <= block.timestamp
    }

    /**
     * Retrieve the current minimum timelock delay before scheduled transactions can be executed.
     * @return duration The minimum timelock delay.
     */
    function getMinDelay() external view returns (uint256 duration);

    /**
     * Updates the minimum timelock delay.
     * @notice Only the timelock itself can make updates to the timelock delay.
     * @param newMinDelay The new minimum delay. Must be at least MIN_DELAY and no greater than MAX_DELAY.
     */
    function updateMinDelay(uint256 newMinDelay) external;

    /**
     * Returns the nonce value for the next operation.
     * @return opNonce The nonce for the next operation.
     */
    function getNextOperationNonce() external view returns (uint256 opNonce);

    /**
     * Returns the OperationStatus of the provided operation nonce.
     * @notice Non-existing operations will return OperationStatus.NoOp (which is uint8(0)).
     * @param opNonce The operation nonce.
     * @return opStatus The OperationStatus value.
     */
    function getOperationStatus(uint256 opNonce) external view returns (OperationStatus opStatus);

    /**
     * Returns the address of the module that enabled the operation with the specified nonce.
     * @notice Reverts if the operation does not exist.
     * @param opNonce The operation nonce.
     * @return module The address of the module.
     */
    function getOperationModule(uint256 opNonce) external view returns (address module);

    /**
     * Returns the hash of the target, value, and calldata for the operation with the specified nonce.
     * @notice Reverts if the operation does not exist.
     * @param opNonce The operation nonce.
     * @return opHash The hash of the operation's target, value, and calldata.
     */
    function getOperationHash(uint256 opNonce) external view returns (bytes32 opHash);

    /**
     * Returns the timestamp when the operation will be executable.
     * @notice Reverts if the operation does not exist.
     * @param opNonce The operation nonce.
     * @return executableAt The timestamp when the operation is executable.
     */
    function getOperationExecutableAt(uint256 opNonce) external view returns (uint256 executableAt);

    /**
     * Returns the details for the provided operation nonce.
     * @notice Reverts if the operation does not exist.
     * @param opNonce The operation nonce.
     * @return module The module that scheduled the operation.
     * @return executableAt Timestamp when this operation is executable.
     * @return createdAt Timestamp when this operation was created.
     * @return opHash The hash of the operation's target, value, and calldata.
     */
    function getOperationDetails(
        uint256 opNonce
    ) external view returns (
        address module,
        uint256 executableAt,
        uint256 createdAt,
        bytes32 opHash
    );

    /**
     * Schedules a transaction for execution (with return data).
     * @notice The msg.sender must be an enabled module.
     * @param to The target for execution.
     * @param value The call value.
     * @param data The call data.
     * @param operation For this timelock, must be Enum.Operation.Call (which is uint8(0))
     * @param delay The delay before the transaction can be executed.
     * @return success Returns true for successful scheduling
     * @return returnData Returns abi.encode(uint256 opNonce,bytes32 opHash,uint256 executableAt).
     */
    function scheduleTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        uint256 delay
    ) external returns (bool success, bytes memory returnData);

    /**
     * Executes a scheduled operation.
     * @notice Requires that an execution call comes from the same module that originally scheduled the operation.
     * @param opNonce The operation nonce.
     * @param to The target for execution.
     * @param value The call value.
     * @param data The call data.
     * @param operation The operation type. Must be Enum.Operation.Call (which is uint8(0)).
     */
    function executeOperation(
        uint256 opNonce,
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    ) external;

    /**
     * Cancels a scheduled operation.
     * @notice Requires that a cancel call comes from the same module that originally scheduled the operation.
     * @param opNonce The operation nonce.
     */
    function cancelOperation(uint256 opNonce) external;

    /**
     * Utility method for creating the opHash for an operation. Hashes the "to", the "value", the "data", and the
     * "operation"
     * @param to The operation target address.
     * @param value The oepration ETH value.
     * @param data The operation's calldata.
     * @param operation The operation type.
     * @return opHash The keccak256 hash of the abi encoded to, value, data, and operation.
     */
    function hashOperation(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    ) external pure returns (bytes32 opHash);

}