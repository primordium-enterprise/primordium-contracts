// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {Enum} from "contracts/common/Enum.sol";
import {SelfAuthorized} from "./SelfAuthorized.sol";

/**
 * @title Executor Base Call Only - Only allows CALL operations (no DELEGATECALL)
 *
 * @author Ben Jett @BCJdevelopment
 */
abstract contract ExecutorBaseCallOnly is SelfAuthorized {

    event CallExecuted(address indexed target, uint256 value, bytes data, Enum.Operation operation);

    error ExecutorIsCallOnly();
    error CallReverted(address target, uint256 value, bytes data, Enum.Operation operation);

    /**
     * @dev Contract should be able to receive ETH.
     */
    receive() external payable virtual {}

    fallback() external payable virtual {}

    /**
     * @dev Execute an operation's call.
     */
    function _execute(
        address target,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    ) internal virtual {
        if (operation != Enum.Operation.Call) {
            revert ExecutorIsCallOnly();
        }
        (bool success,) = target.call{value: value}(data);
        if (!success) revert CallReverted(target, value, data, operation);
        emit CallExecuted(target, value, data, operation);
    }

}