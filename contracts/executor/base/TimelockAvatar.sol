// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.4;

import {Enum} from "contracts/common/Enum.sol";
import {MultiSend} from "./MultiSend.sol";
import {IAvatar} from "../interfaces/IAvatar.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title Timelock Avatar implements a timelock control on all call executions for the Executor.
 *
 * @dev This contract follows the IAvatar interface for the Zodiac Modular Accounts standard from EIP-5005.
 *
 * @author Ben Jett @BCJdevelopment
 */
abstract contract TimelockAvatar is MultiSend, IAvatar {

    enum OperationStatus {
        NoOp, // NoOp when executableAt == 0
        Cancelled, // Cancelled when executableAt == 1
        Done, // Done when executableAt == 2
        Pending, // Pending when executableAt > block.timestamp
        Ready, // Ready when executableAt <= block.timestamp (and not expired)
        Expired // Expired when executableAt + GRACE_PERIOD <= block.timestamp
    }

    struct Operation {
        address module;
        uint48 executableAt;
        uint48 createdAt;
        bytes32 opHash;
    }

    address internal constant MODULES_HEAD = address(0x1);
    mapping(address => address) internal _modules;

    uint256 public constant GRACE_PERIOD = 14 days;
    uint256 public constant MIN_DELAY = 2 days;
    uint256 public constant MAX_DELAY = 30 days;
    uint256 private _minDelay;

    uint256 internal _opNonce;
    mapping(uint256 => Operation) _operations;

    /**
     * @dev Emitted when the minimum delay for future operations is modified.
     */
    event MinDelayUpdate(uint256 oldMinDelay, uint256 newMinDelay);

    event ModulesInitialized(address[] modules_);

    event OperationScheduled(
        uint256 indexed opNonce,
        address indexed module,
        address to,
        uint256 value,
        bytes data,
        uint256 delay
    );

    event OperationExecuted(
        uint256 indexed opNonce,
        address indexed module,
        address to,
        uint256 value,
        bytes data
    );

    event OperationCancelled(uint256 indexed opNonce, address indexed module);

    error MinDelayOutOfRange(uint256 min, uint256 max);
    error InsufficientDelay();
    error ModuleNotEnabled(address module);
    error ModulesAlreadyInitialized();
    error ModuleInitializationNeedsMoreThanZeroModules();
    error InvalidModuleAddress(address module);
    error ModuleAlreadyEnabled(address module);
    error InvalidPreviousModuleAddress(address prevModule);
    error InvalidStartModule(address start);
    error InvalidPageSize(uint256 pageSize);
    error InvalidOperationStatus(OperationStatus currentStatus, OperationStatus requiredStatus);
    error UnauthorizedModule();
    error InvalidCallParameters();

    /**
     * Modifier for only enabled modules to take the specified action
     */
    modifier onlyModule() {
        if (!isModuleEnabled(msg.sender)) revert ModuleNotEnabled(msg.sender);
        _;
    }

    function __ModuleTimelockAdmin_init(
        uint256 minDelay_,
        address[] memory modules_
    ) internal {
        _updateMinDelay(minDelay_);
        _setUpModules(modules_);
    }

    /**
     * @dev Initialization of an array of modules. The provided array must have at least one module, or else the
     * contract is bricked (no modules to enable other modules).
     * @param modules_ An array of initial module addresses to enable.
     */
    function _setUpModules(address[] memory modules_) internal {
        if (_modules[MODULES_HEAD] != address(0)) {
            revert ModulesAlreadyInitialized();
        }
        if (modules_.length == 0) {
            revert ModuleInitializationNeedsMoreThanZeroModules();
        }
        _modules[MODULES_HEAD] = MODULES_HEAD;
        // Enable the provided modules
        for (uint256 i = 0; i < modules_.length;) {
            _enableModule(modules_[i]);
            unchecked { ++i; }
        }
        emit ModulesInitialized(modules_);
    }

    /**
     * Retrieve the current minimum timelock delay before scheduled transactions can be executed.
     * @return duration The minimum timelock delay.
     */
    function getMinDelay() public view returns (uint256 duration) {
        return _minDelay;
    }

    /**
     * Updates the minimum timelock delay.
     * @notice Only the timelock itself can make updates to the timelock delay.
     * @param newMinDelay The new minimum delay. Must be at least MIN_DELAY and no greater than MAX_DELAY.
     */
    function updateMinDelay(uint256 newMinDelay) external onlyExecutor {
        _updateMinDelay(newMinDelay);
    }

    /// @dev Internal function to update the _minDelay.
    function _updateMinDelay(uint256 newMinDelay) internal {
        if (
            newMinDelay < MIN_DELAY ||
            newMinDelay > MAX_DELAY
        ) revert MinDelayOutOfRange(MIN_DELAY, MAX_DELAY);

        emit MinDelayUpdate(_minDelay, newMinDelay);
        _minDelay = newMinDelay;
    }

    /**
     * Returns the nonce value for the next operation.
     * @return opNonce The nonce for the next operation.
     */
    function getNextOperationNonce() external view returns (uint256 opNonce) {
        return _opNonce;
    }

    /**
     * Returns the OperationStatus of the provided operation nonce.
     * @notice Non-existing operations will return OperationStatus.NoOp (which is uint8(0)).
     * @param opNonce The operation nonce.
     * @return opStatus The OperationStatus value.
     */
    function getOperationStatus(uint256 opNonce) external view returns (OperationStatus opStatus) {
        opStatus = _getOperationStatus(_operations[opNonce].executableAt);
    }

    /// @dev Internal utility to return the OperationStatus enum value based on the operation eta
    function _getOperationStatus(uint256 eta) internal view returns (OperationStatus opStatus) {
        // ETA timestamp is equal to the enum value for NoOp, Cancelled, and Done
        if (eta > uint256(OperationStatus.Done)) {
            if (eta <= block.timestamp) {
                if (eta + GRACE_PERIOD <= block.timestamp) return OperationStatus.Expired;
                return OperationStatus.Ready;
            }
            return OperationStatus.Pending;
        }
        return OperationStatus(eta);
    }

    /**
     * Returns the address of the module that enabled the operation with the specified nonce.
     * @notice Reverts if the operation does not exist.
     * @param opNonce The operation nonce.
     * @return module The address of the module.
     */
    function getOperationModule(uint256 opNonce) external view returns (address module) {
        _checkOpNonce(opNonce);
        module = _operations[opNonce].module;
    }

    /**
     * Returns the hash of the target, value, and calldata for the operation with the specified nonce.
     * @notice Reverts if the operation does not exist.
     * @param opNonce The operation nonce.
     * @return opHash The hash of the operation's target, value, and calldata.
     */
    function getOperationHash(uint256 opNonce) external view returns (bytes32 opHash) {
        _checkOpNonce(opNonce);
        opHash = _operations[opNonce].opHash;
    }

    /**
     * Returns the timestamp when the operation will be executable.
     * @notice Reverts if the operation does not exist.
     * @param opNonce The operation nonce.
     * @return executableAt The timestamp when the operation is executable.
     */
    function getOperationExecutableAt(uint256 opNonce) external view returns (uint256 executableAt) {
        _checkOpNonce(opNonce);
        executableAt = _operations[opNonce].executableAt;
    }

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
    ) {
        _checkOpNonce(opNonce);
        Operation storage op = _operations[opNonce];
        (
            module,
            executableAt,
            createdAt,
            opHash
        ) = (
            op.module,
            op.executableAt,
            op.createdAt,
            op.opHash
        );
    }

    /**
     * @notice Authorizes a new module to execute transactions on this Executor contract. Modules can only be enabled
     * by this contract itself.
     * @param module The address of the module to enable.
     */
    function enableModule(address module) external onlyExecutor {
        _enableModule(module);
    }

    /// @dev Internal function to enable a new module. Emits EnabledModule(address)
    function _enableModule(address module) internal {
        // Make sure the module is a valid address to enable.
        if (module == address(0) || module == MODULES_HEAD) revert InvalidModuleAddress(module);
        if (_modules[module] != address(0)) revert ModuleAlreadyEnabled(module);
        _modules[module] = MODULES_HEAD;
        _modules[MODULES_HEAD] = module;
        emit EnabledModule(module);
    }

    /**
     * @notice Unauthorizes an enabled module.
     * @param module The address of the module to disable.
     */
    function disableModule(address prevModule, address module) external onlyExecutor {
        _disableModule(prevModule, module);
    }

    /// @dev Internal function to disable a new module. Emits DisabledModule(address)
    function _disableModule(address prevModule, address module) internal {
        // Make sure the module is currently active
        if (module == address(0) || module == MODULES_HEAD) revert InvalidModuleAddress(module);
        if (_modules[prevModule] != module) revert InvalidPreviousModuleAddress(prevModule);
        _modules[prevModule] = _modules[module];
        _modules[module] = address(0);
        emit DisabledModule(module);
    }

    /**
     * Schedules a transaction for execution.
     * @notice The msg.sender must be an enabled module.
     * @param to The target for execution.
     * @param value The call value.
     * @param data The call data.
     * @param operation For this timelock, must be Enum.Operation.Call (or uint8(0)).
     * @return success Returns true for successful scheduling.
     */
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    ) external onlyModule returns (bool success) {
        // Operations are CALL only for this timelock
        if (operation != Enum.Operation.Call) revert ExecutorIsCallOnly();
        (success,) = _scheduleTransactionFromModule(msg.sender, to, value, data, _minDelay);
    }

    /**
     * Schedules a transaction for execution (with return data).
     * @notice The msg.sender must be an enabled module.
     * @param to The target for execution.
     * @param value The call value.
     * @param data The call data.
     * @param operation For this timelock, must be Enum.Operation.Call (or uint8(0)).
     * @return success Returns true for successful scheduling
     * @return returnData Returns abi.encode(uint256 opNonce,bytes32 opHash,uint256 executableAt).
     */
    function execTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    ) external onlyModule returns (bool success, bytes memory returnData) {
        // Operations are CALL only for this timelock
        if (operation != Enum.Operation.Call) revert ExecutorIsCallOnly();
        (success, returnData) = _scheduleTransactionFromModule(msg.sender, to, value, data, _minDelay);
    }

    /**
     * Schedules a transaction for execution (with return data).
     * @notice The msg.sender must be an enabled module.
     * @param to The target for execution.
     * @param value The call value.
     * @param data The call data.
     * @param delay The delay before the transaction can be executed.
     * @return success Returns true for successful scheduling
     * @return returnData Returns abi.encode(uint256 opNonce,bytes32 opHash,uint256 executableAt).
     */
    function scheduleTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes calldata data,
        uint256 delay
    ) external onlyModule returns (bool success, bytes memory returnData) {
        // Delay must be greater than the minDelay
        if (delay < _minDelay) revert InsufficientDelay();
        (success, returnData) = _scheduleTransactionFromModule(msg.sender, to, value, data, delay);
    }

    function _scheduleTransactionFromModule(
        address module,
        address to,
        uint256 value,
        bytes calldata data,
        uint256 delay
    ) internal returns (bool, bytes memory) {
        // Set opNonce and increment
        uint256 opNonce = _opNonce++;

        bytes32 opHash = hashOperation(to, value, data);
        uint256 executableAt = block.timestamp + delay;

        _operations[opNonce] = Operation({
            module: module,
            createdAt: SafeCast.toUint48(block.timestamp),
            executableAt: SafeCast.toUint48(executableAt),
            opHash: opHash
        });

        emit OperationScheduled(opNonce, module, to, value, data, delay);

        return (true, abi.encode(opNonce, opHash, executableAt));
    }

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
    ) external {
        Operation storage op = _operations[opNonce];
        (address module, uint256 executableAt) = (op.module, op.executableAt);

        if (msg.sender != module) revert UnauthorizedModule();

        OperationStatus opStatus = _getOperationStatus(executableAt);
        if (opStatus != OperationStatus.Ready) revert InvalidOperationStatus(opStatus, OperationStatus.Ready);

        bytes32 opHash = hashOperation(to, value, data);
        if (opHash != op.opHash) revert InvalidCallParameters();

        _execute(to, value, data, operation);

        // Check that the operation status is still "ready" to protect against re-entrancy messing with the operation
        opStatus = _getOperationStatus(executableAt);
        if (opStatus != OperationStatus.Ready) revert InvalidOperationStatus(opStatus, OperationStatus.Ready);
        op.executableAt = uint48(OperationStatus.Done);

        emit OperationExecuted(opNonce, module, to, value, data);
    }

    /**
     * Cancels a scheduled operation.
     * @notice Requires that a cancel call comes from the same module that originally scheduled the operation.
     * @param opNonce The operation nonce.
     */
    function cancelOperation(uint256 opNonce) external {
        Operation storage op = _operations[opNonce];
        (address module, uint256 executableAt) = (op.module, op.executableAt);

        if (msg.sender != module) revert UnauthorizedModule();

        OperationStatus opStatus = _getOperationStatus(executableAt);
        if (opStatus != OperationStatus.Pending) revert InvalidOperationStatus(opStatus, OperationStatus.Pending);

        op.executableAt = uint48(OperationStatus.Cancelled);

        emit OperationCancelled(opNonce, module);
    }

    /**
     * Returns true if the specified module is enabled.
     * @param module The module address
     * @return enabled
     */
    function isModuleEnabled(address module) public view returns(bool enabled) {
        return module != MODULES_HEAD && _modules[module] != address(0);
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
        next = _modules[start];
        while(count < pageSize && next != MODULES_HEAD && next != address(0)) {
            array[count] = next;
            next = _modules[next];
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

    /**
     * Utility method for creating the opHash for an operation. Hashes the "to", the "value", and the "data".
     * @param to The operation target address.
     * @param value The oepration ETH value.
     * @param data The operation's calldata.
     * @return opHash The keccak256 hash of the abi encoded to, value, and data.
     */
    function hashOperation(
        address to,
        uint256 value,
        bytes calldata data
    ) public pure returns (bytes32 opHash) {
        opHash = keccak256(abi.encode(to, value, data));
    }

    /// @dev An internal utility function to revert if the provided operation nonce does not exist
    function _checkOpNonce(uint256 opNonce) internal view {
        if (opNonce >= _opNonce) revert();
    }

}