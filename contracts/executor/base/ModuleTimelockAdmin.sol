// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.4;

import {Enum} from "contracts/common/Enum.sol";
import {MultiSend} from "./MultiSend.sol";
import {IAvatar} from "../interfaces/IAvatar.sol";

/**
 * @title Module Timelock Admin implements a timelock control on all call executions for the Executor.
 *
 * @dev This contract follows the IAvatar interface for the Zodiac Modular Accounts standard from EIP-5005.
 *
 * @author Ben Jett @BCJdevelopment
 */
abstract contract ModuleTimelockAdmin is MultiSend, IAvatar {

    // For "modules" linked list
    address internal constant MODULES_HEAD = address(0x1);

    mapping(address => address) internal modules;

    event ModulesInitialized(address[] modules_);

    error ModulesAlreadyInitialized();
    error ModuleInitializationNeedsMoreThanZeroModules();
    error InvalidModuleAddress(address module);
    error ModuleAlreadyEnabled(address module);
    error InvalidPreviousModuleAddress(address prevModule);
    error InvalidStartModule(address start);
    error InvalidPageSize(uint256 pageSize);

    /**
     * @dev Initialization of an array of modules. The provided array must have at least one module, or else this
     * contract will be bricked (no modules to enable other modules).
     * @param modules_ An array of initial module addresses to enable.
     */
    function __ModuleTimelockAdmin_init(address[] memory modules_) internal {
        if (modules[MODULES_HEAD] != address(0)) {
            revert ModulesAlreadyInitialized();
        }
        if (modules_.length == 0) {
            revert ModuleInitializationNeedsMoreThanZeroModules();
        }
        modules[MODULES_HEAD] = MODULES_HEAD;
        // Enable the provided modules
        for (uint256 i = 0; i < modules_.length;) {
            // TODO: Enable each module
            unchecked { ++i; }
        }
        emit ModulesInitialized(modules_);
    }


    /**
     * @notice Authorizes a new module to execute transactions on this Executor contract. Modules can only be enabled
     * by this contract itself.
     * @param module The address of the module to enable.
     */
    function enableModule(address module) external onlyExecutor {
        _enableModule(module);
    }

    function _enableModule(address module) internal {
        // Make sure the module is a valid address to enable.
        if (module == address(0) || module == MODULES_HEAD) revert InvalidModuleAddress(module);
        if (modules[module] != address(0)) revert ModuleAlreadyEnabled(module);
        modules[module] = MODULES_HEAD;
        modules[MODULES_HEAD] = module;
        emit EnabledModule(module);
    }

    function disableModule(address prevModule, address module) external onlyExecutor {
        _disableModule(prevModule, module);
    }

    function _disableModule(address prevModule, address module) internal {
        // Make sure the module is currently active
        if (module == address(0) || module == MODULES_HEAD) revert InvalidModuleAddress(module);
        if (modules[prevModule] != module) revert InvalidPreviousModuleAddress(prevModule);
        modules[prevModule] = modules[module];
        modules[module] = address(0);
        emit DisabledModule(module);
    }

    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    ) external returns (bool success) {
        // Operations are CALL only for this timelock
        if (operation != Enum.Operation.Call) revert ExecutorIsCallOnly();
        (success,) = _execTransactionFromModule(to, value, data);
    }

    function execTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    ) external returns (bool success, bytes memory returnData) {
        // Operations are CALL only for this timelock
        if (operation != Enum.Operation.Call) revert ExecutorIsCallOnly();
        (success, returnData) = _execTransactionFromModule(to, value, data);
    }

    function _execTransactionFromModule(
        address to,
        uint256 value,
        bytes calldata data
    ) internal returns (bool, bytes memory) {

    }

    function isModuleEnabled(address module) public view returns(bool) {
        return module != MODULES_HEAD && modules[module] != address(0);
    }

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
    ) external view returns (
        address[] memory array,
        address next
    ) {
        // Check the start address and page size
        if (start != MODULES_HEAD && !isModuleEnabled(start)) revert InvalidStartModule(start);
        if (pageSize == 0) revert InvalidPageSize(pageSize);

        // Init array
        array = new address[](pageSize);

        // Init count and iterate through modules
        uint256 count = 0;
        next = modules[start];
        while(count < pageSize && next != MODULES_HEAD && next != address(0)) {
            array[count] = next;
            next = modules[next];
            count++;
        }

        // If not at the end, set "next" to the end of the current list to serve as a pointer for next page
        if (next != MODULES_HEAD) {
            next = array[count - 1];
        }

        // Set the proper array length
        /// @solidity memory-safe-assembly
        assembly {
            mstore(array, count)
        }

    }


}