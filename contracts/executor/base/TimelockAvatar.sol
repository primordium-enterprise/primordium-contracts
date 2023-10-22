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

    struct Operation {
        address module;
        uint48 createdAt;
        uint48 executableAt;
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

    uint256 internal constant _DONE_TIMESTAMP = uint256(1);

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

    function getNextOperationNonce() external view returns (uint256 opNonce) {
        return _opNonce;
    }

    function isOperation(uint256 opNonce) external view returns (bool isOp) {
        return _isOp(_operations[opNonce].executableAt);
    }

    function isOperationPending(uint256 opNonce) external view returns (bool isOpPending) {
        return _isOpPending(_operations[opNonce].executableAt);
    }

    function isOperationReady(uint256 opNonce) external view returns (bool isOpReady) {
        return _isOpReady(_operations[opNonce].executableAt);
    }

    function isOperationExpired(uint256 opNonce) external view returns (bool isOpExpired) {
        return _isOpExpired(_operations[opNonce].executableAt);
    }

    function isOperationDone(uint256 opNonce) external view returns (bool isOpDone) {
        return _isOpDone(_operations[opNonce].executableAt);
    }

    function getOperationInfo(
        uint256 opNonce
    ) external view returns (
        address module,
        uint256 createdAt,
        uint256 executableAt,
        bytes32 opHash
    ) {

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
     * @return returnData
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
     * @return returnData
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

        // Set the hash and executable at parameters
        bytes32 opHash = hashOperation(to, value, data);
        uint256 executableAt = block.timestamp + delay;

        // Save to storage
        _operations[opNonce] = Operation({
            module: module,
            createdAt: SafeCast.toUint48(block.timestamp),
            executableAt: SafeCast.toUint48(executableAt),
            opHash: opHash
        });

        emit OperationScheduled(opNonce, module, to, value, data, delay);

        return (true, abi.encode(opNonce, opHash, executableAt));
    }

    function isModuleEnabled(address module) public view returns(bool) {
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

    function hashOperation(
        address to,
        uint256 value,
        bytes calldata data
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(to, value, data));
    }

    function _isOp(uint256 executableAt) internal pure returns (bool) {
        return executableAt > 0;
    }

    function _isOpPending(uint256 executableAt) internal pure returns (bool) {
        return executableAt > _DONE_TIMESTAMP;
    }

    function _isOpReady(uint256 executableAt) internal view returns (bool) {
        return !_isOpExpired(executableAt) && executableAt <= block.timestamp;
    }

    function _isOpExpired(uint256 executableAt) internal view returns (bool) {
        return _isOpPending(executableAt) && executableAt + GRACE_PERIOD >= block.timestamp;
    }

    function _isOpDone(uint256 executableAt) internal pure returns (bool) {
        return executableAt == _DONE_TIMESTAMP;
    }

}