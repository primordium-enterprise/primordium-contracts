// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.4;

/**
 * @title Executor Base Call Only - Only allows CALL operations (no DELEGATECALL)
 */
abstract contract ExecutorBaseCallOnly {

    /**
     * Throws when a call fails to execute.
     */
    error OperationCallReverted(address target, uint256 value, bytes data);

    /**
     * @dev Execute an operation's call.
     */
    function _execute(
        address target,
        uint256 value,
        bytes calldata data
    ) internal virtual {
        (bool success,) = target.call{value: value}(data);
        if (!success) revert OperationCallReverted(target, value, data);
    }

}