// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {Enum} from "src/common/Enum.sol";

/**
 * @title Avatar interface, based on EIP-5005 for Zodiac Modular Accounts
 */
interface IAvatar {
    event EnabledModule(address indexed module);
    event DisabledModule(address indexed module);
    event ExecutionFromModuleSuccess(address indexed module);
    event ExecutionFromModuleFailure(address indexed module);

    /**
     * Authorizes a new module to execute transactions on this avatar contract. Modules can only be enabled
     * by this contract itself.
     * @notice Enabled modules are stored as a linked list.
     * @dev Can only be called by this contract itself.
     * @param module The address of the module to enable.
     */
    function enableModule(address module) external;

    /**
     * Unauthorizes an enabled module.
     * @dev Can only be called by this contract itself.
     * @param prevModule Addres that pointed to the module to be removed in the linked list.
     * @param module The address of the module to disable.
     */
    function disableModule(address prevModule, address module) external;

    /// @dev Allows a Module to execute a transaction.
    /// @dev Can only be called by an enabled module.
    /// @notice Must emit ExecutionFromModuleSuccess(address module) if successful.
    /// @notice Must emit ExecutionFromModuleFailure(address module) if unsuccessful.
    /// @param to Destination address of module transaction.
    /// @param value Ether value of module transaction.
    /// @param data Data payload of module transaction.
    /// @param operation Operation type of module transaction: 0 == call, 1 == delegate call.
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    )
        external
        returns (bool success);

    /// @dev Allows a Module to execute a transaction and return data
    /// @notice Can only be called by an enabled module.
    /// @notice Must emit ExecutionFromModuleSuccess(address module) if successful.
    /// @notice Must emit ExecutionFromModuleFailure(address module) if unsuccessful.
    /// @param to Destination address of module transaction.
    /// @param value Ether value of module transaction.
    /// @param data Data payload of module transaction.
    /// @param operation Operation type of module transaction: 0 == call, 1 == delegate call.
    function execTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    )
        external
        returns (bool success, bytes memory returnData);

    /**
     * Returns true if the specified module is enabled.
     * @param module The module address.
     * @return enabled True of the module is enabled.
     */
    function isModuleEnabled(address module) external view returns (bool);

    /**
     * @notice Returns an array of enabled modules.
     * @param start The start address. Use the 0x1 address to start at the beginning.
     * @param pageSize The amount of modules to return.
     * @return array The array of module addresses.
     * @return next Use as the start parameter to retrieve the next page of modules. Will be 0x1 at end of modules.
     */
    function getModulesPaginated(
        address start,
        uint256 pageSize
    )
        external
        view
        returns (address[] memory array, address next);
}
