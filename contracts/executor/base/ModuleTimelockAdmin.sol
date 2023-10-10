// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.4;

import {Enum} from "contracts/common/Enum.sol";
import {MultiSendCallOnly} from "./MultiSendCallOnly.sol";
import {IAvatar} from "../interfaces/IAvatar.sol";

/**
 * @title Module Timelock Admin implements a timelock control on all call executions for the Executor.
 *
 * @dev This contract follows the IAvatar interface for the Zodiac Modular Accounts standard from EIP-5005.
 *
 * @author Ben Jett @BCJdevelopment
 */
abstract contract ModuleTimelockAdmin is MultiSendCallOnly, IAvatar {

    // For "modules" linked list
    address internal constant MODULES_HEAD = address(0x1);

    mapping(address => address) internal modules;

    event ModulesInitialized(address[] modules_);

    error ModulesAlreadyInitialized();
    error ModuleInitializationNeedsMoreThanZeroModules();
    error InvalidModuleAddress(address module);
    error ModuleAlreadyEnabled(address module);
    error InvalidPreviousModuleAddress(address prevModule);

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


}