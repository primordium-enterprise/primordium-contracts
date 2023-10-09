// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.4;

import {Enum} from "contracts/common/Enum.sol";

/**
 * @title Executor Base Call Only - Only allows CALL operations (no DELEGATECALL)
 */
abstract contract ExecutorBaseCallOnly {

    error OnlyExecutor();

    error ExecutorIsCallOnly();

    /**
     * Throws when a call fails to execute.
     */
    error OperationCallReverted(address target, uint256 value, bytes data);

    /**
     * @dev Modifier to make a function callable only by the Executor itself, meaning this Executor contract must make
     * the call through it's own _execute() function.
     */
    modifier onlyExecutor {
        _onlyExecutor();
        _;
    }

    function _onlyExecutor() private view {
        if (msg.sender != address(this)) {
            revert OnlyExecutor();
        }
    }

    /**
     * @dev Execute an operation's call.
     */
    function _execute(
        address target,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    ) internal virtual {
        if (operation > Enum.Operation.Call) {
            revert ExecutorIsCallOnly();
        }
        (bool success,) = target.call{value: value}(data);
        if (!success) revert OperationCallReverted(target, value, data);
    }

}