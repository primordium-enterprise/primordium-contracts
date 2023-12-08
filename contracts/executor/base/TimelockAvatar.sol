// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {Enum} from "contracts/common/Enum.sol";
import {MultiSend} from "./MultiSend.sol";
import {Guardable} from "./Guardable.sol";
import {IAvatar} from "../interfaces/IAvatar.sol";
import {IGuard} from "../interfaces/IGuard.sol";
import {ITimelockAvatar} from "../interfaces/ITimelockAvatar.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

/**
 * @title Timelock Avatar implements a timelock control on all call executions for the Executor.
 *
 * @dev This contract follows the IAvatar interface for the Zodiac Modular Accounts standard from EIP-5005.
 *
 * @author Ben Jett @BCJdevelopment
 */
abstract contract TimelockAvatar is
    MultiSend,
    IAvatar,
    ITimelockAvatar,
    Guardable,
    ERC721Holder,
    ERC1155Holder
{

    struct Operation {
        address module;
        uint48 executableAt;
        uint48 createdAt;
        bytes32 opHash;
    }

    /// @custom:storage-location erc7201:TimelockAvatar.ModuleExecution.Storage
    struct ModuleExecutionStorage {
        address _executingModule;
    }

    bytes32 private immutable MODULE_EXECUTION_STORAGE = keccak256(
        abi.encode(uint256(keccak256("TimelockAvatar.ModuleExecution.Storage")) - 1)) & ~bytes32(uint256(0xff)
    );

    function _getModuleExecutionStorage() private view returns (ModuleExecutionStorage storage $) {
        bytes32 slot = MODULE_EXECUTION_STORAGE;
        assembly {
            $.slot := slot
        }
    }

    /// @custom:storage-location erc7201:TimelockAvatar.Timelock.Storage
    struct TimelockStorage {
        mapping(address => address) _modules;

        uint256 _minDelay;
        uint256 _opNonce;
        mapping(uint256 => Operation) _operations;
    }

    bytes32 private immutable TIMELOCK_STORAGE = keccak256(
        abi.encode(uint256(keccak256("TimelockAvatar.Timelock.Storage")) - 1)) & ~bytes32(uint256(0xff)
    );

    function _getTimelockStorage() private view returns (TimelockStorage storage $) {
        bytes32 slot = TIMELOCK_STORAGE;
        assembly {
            $.slot := slot
        }
    }

    address internal constant MODULES_HEAD = address(0x1);

    uint256 public constant GRACE_PERIOD = 14 days;
    uint256 public constant MIN_DELAY = 2 days;
    uint256 public constant MAX_DELAY = 30 days;

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
        Enum.Operation operation,
        uint256 delay
    );

    event OperationExecuted(
        uint256 indexed opNonce,
        address indexed module,
        address to,
        uint256 value,
        bytes data,
        Enum.Operation operation
    );

    event OperationCancelled(uint256 indexed opNonce, address indexed module);

    error MinDelayOutOfRange(uint256 min, uint256 max);
    error InsufficientDelay();
    error ModuleNotEnabled(address module);
    error SenderMustBeExecutingModule(address sender, address executingModule);
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

    /// @dev Only enabled modules to take the specified action.
    modifier onlyModule() {
        if (!isModuleEnabled(msg.sender)) {
            revert ModuleNotEnabled(msg.sender);
        }
        _;
    }

    /// @dev Only allows the function to be called by the module actively executing the current operation.
    modifier onlyDuringModuleExecution() {
        _onlyDuringModuleExecution();
        _;
    }

    modifier onlySelfOrDuringModuleExecution() {
        if (msg.sender != address(this)) {
            _onlyDuringModuleExecution();
        }
        _;
    }

    function _onlyDuringModuleExecution() internal view {
        address _executingModule = executingModule();
        if (msg.sender != _executingModule) {
            revert SenderMustBeExecutingModule(msg.sender, _executingModule);
        }
    }

    /// @dev Returns the module that is actively executing the operation.
    function executingModule() public view returns (address module) {
        return _getModuleExecutionStorage()._executingModule;
    }

    function __ModuleTimelockAdmin_init(
        uint256 minDelay_,
        address[] memory modules_
    ) internal onlyInitializing {
        __SelfAuthorized_init();
        // Initialize the module execution to address(0x01) for cheaper gas updates
        _setModuleExecution(MODULES_HEAD);
        _updateMinDelay(minDelay_);
        _setUpModules(modules_);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155Holder, Guardable) returns (bool) {
        return
            interfaceId == type(IAvatar).interfaceId ||
            interfaceId == type(ITimelockAvatar).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Initialization of an array of modules. The provided array must have at least one module, or else the
     * contract is bricked (no modules to enable other modules).
     * @param modules_ An array of initial module addresses to enable.
     */
    function _setUpModules(address[] memory modules_) internal {
        TimelockStorage storage $ = _getTimelockStorage();

        if ($._modules[MODULES_HEAD] != address(0)) {
            revert ModulesAlreadyInitialized();
        }

        if (modules_.length == 0) {
            revert ModuleInitializationNeedsMoreThanZeroModules();
        }

        // Initialize modules head
        $._modules[MODULES_HEAD] = MODULES_HEAD;

        // Enable the provided modules
        for (uint256 i = 0; i < modules_.length;) {
            _enableModule(modules_[i]);
            unchecked { ++i; }
        }

        emit ModulesInitialized(modules_);
    }

    /// @inheritdoc ITimelockAvatar
    function getMinDelay() public view returns (uint256 duration) {
        duration = _getTimelockStorage()._minDelay;
    }

    /// @inheritdoc ITimelockAvatar
    function updateMinDelay(uint256 newMinDelay) external onlySelf {
        _updateMinDelay(newMinDelay);
    }

    /// @dev Internal function to update the _minDelay.
    function _updateMinDelay(uint256 newMinDelay) internal {
        TimelockStorage storage $ = _getTimelockStorage();

        if (
            newMinDelay < MIN_DELAY ||
            newMinDelay > MAX_DELAY
        ) {
            revert MinDelayOutOfRange(MIN_DELAY, MAX_DELAY);
        }

        emit MinDelayUpdate($._minDelay, newMinDelay);
        $._minDelay = newMinDelay;
    }

    /// @inheritdoc ITimelockAvatar
    function getNextOperationNonce() external view returns (uint256 opNonce) {
        opNonce = _getTimelockStorage()._opNonce;
    }

    /// @inheritdoc ITimelockAvatar
    function getOperationStatus(uint256 opNonce) external view returns (OperationStatus opStatus) {
        opStatus = _getOperationStatus(
            _getTimelockStorage()._operations[opNonce].executableAt
        );
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

    /// @inheritdoc ITimelockAvatar
    function getOperationModule(uint256 opNonce) external view returns (address module) {
        TimelockStorage storage $ = _getTimelockStorage();
        _checkOpNonce($, opNonce);
        module = $._operations[opNonce].module;
    }

    /// @inheritdoc ITimelockAvatar
    function getOperationHash(uint256 opNonce) external view returns (bytes32 opHash) {
        TimelockStorage storage $ = _getTimelockStorage();
        _checkOpNonce($, opNonce);
        opHash = $._operations[opNonce].opHash;
    }

    /// @inheritdoc ITimelockAvatar
    function getOperationExecutableAt(uint256 opNonce) external view returns (uint256 executableAt) {
        TimelockStorage storage $ = _getTimelockStorage();
        _checkOpNonce($, opNonce);
        executableAt = $._operations[opNonce].executableAt;
    }

    /// @inheritdoc ITimelockAvatar
    function getOperationDetails(
        uint256 opNonce
    ) external view returns (
        address module,
        uint256 executableAt,
        uint256 createdAt,
        bytes32 opHash
    ) {
        TimelockStorage storage $ = _getTimelockStorage();
        _checkOpNonce($, opNonce);
        Operation storage _op = $._operations[opNonce];

        module = _op.module;
        executableAt = _op.executableAt;
        createdAt = _op.createdAt;
        opHash = _op.opHash;
    }

    /// @inheritdoc IAvatar
    function enableModule(address module) external onlySelf {
        _enableModule(module);
    }

    /// @dev Internal function to enable a new module. Emits EnabledModule(address)
    function _enableModule(address module) internal {
        TimelockStorage storage $ = _getTimelockStorage();

        // Make sure the module is a valid address to enable.
        if (module == address(0) || module == MODULES_HEAD) {
            revert InvalidModuleAddress(module);
        }

        if ($._modules[module] != address(0)) {
            revert ModuleAlreadyEnabled(module);
        }

        $._modules[module] = MODULES_HEAD;
        $._modules[MODULES_HEAD] = module;
        emit EnabledModule(module);
    }

    /// @inheritdoc IAvatar
    function disableModule(address prevModule, address module) external onlySelf {
        _disableModule(prevModule, module);
    }

    /// @dev Internal function to disable a new module. Emits DisabledModule(address)
    function _disableModule(address prevModule, address module) internal {
        TimelockStorage storage $ = _getTimelockStorage();

        // Make sure the module is currently active
        if (module == address(0) || module == MODULES_HEAD) {
            revert InvalidModuleAddress(module);
        }

        if ($._modules[prevModule] != module) {
            revert InvalidPreviousModuleAddress(prevModule);
        }

        $._modules[prevModule] = $._modules[module];
        $._modules[module] = address(0);
        emit DisabledModule(module);
    }

    /**
     * Schedules a transaction for execution.
     * @notice The msg.sender must be an enabled module.
     * @param to The target for execution.
     * @param value The call value.
     * @param data The call data.
     * @param operation Operation type, call uint8(0) or delegatecall uint8(1).
     * @return success Returns true for successful scheduling.
     */
    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    ) external virtual onlyModule returns (bool success) {
        (success,) = _scheduleTransactionFromModule(msg.sender, to, value, data, operation, 0);
    }

    /**
     * Schedules a transaction for execution (with return data).
     * @notice The msg.sender must be an enabled module.
     * @param to The target for execution.
     * @param value The call value.
     * @param data The call data.
     * @param operation Operation type, call uint8(0) or delegatecall uint8(1).
     * @return success Returns true for successful scheduling
     * @return returnData Returns abi.encode(uint256 opNonce,bytes32 opHash,uint256 executableAt).
     */
    function execTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    ) external virtual onlyModule returns (bool success, bytes memory returnData) {
        (success, returnData) = _scheduleTransactionFromModule(msg.sender, to, value, data, operation, 0);
    }

    /// @inheritdoc ITimelockAvatar
    function scheduleTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        uint256 delay
    ) external onlyModule returns (bool success, bytes memory returnData) {
        (success, returnData) = _scheduleTransactionFromModule(msg.sender, to, value, data, operation, delay);
    }

    /// @dev Internal method to schedule a new transaction from a module.
    function _scheduleTransactionFromModule(
        address module,
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        uint256 delay
    ) internal virtual returns (bool, bytes memory) {
        TimelockStorage storage $ = _getTimelockStorage();

        // Delay must be greater than the minDelay (if zero is passed, set it equal to min delay)
        uint256 minDelay = $._minDelay;
        if (delay == 0) {
            delay = minDelay;
        } else if (delay < minDelay) {
            revert InsufficientDelay();
        }

        // Set opNonce and increment
        uint256 opNonce = $._opNonce++;

        bytes32 opHash = hashOperation(to, value, data, operation);
        uint256 executableAt = block.timestamp + delay;

        Operation storage _op = $._operations[opNonce];
        _op.module = module;
        _op.createdAt = uint48(block.timestamp);
        _op.executableAt = uint48(executableAt);
        _op.opHash = opHash;

        emit OperationScheduled(opNonce, module, to, value, data, operation, delay);

        return (true, abi.encode(opNonce, opHash, executableAt));
    }

    /// @inheritdoc ITimelockAvatar
    function executeOperation(
        uint256 opNonce,
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    ) external virtual {
        TimelockStorage storage $ = _getTimelockStorage();

        Operation storage _op = $._operations[opNonce];
        (address module, uint256 executableAt) = (_op.module, _op.executableAt);

        if (msg.sender != module) {
            revert UnauthorizedModule();
        }

        OperationStatus opStatus = _getOperationStatus(executableAt);
        if (opStatus != OperationStatus.Ready) {
            revert InvalidOperationStatus(opStatus, OperationStatus.Ready);
        }

        bytes32 opHash = hashOperation(to, value, data, operation);
        if (opHash != _op.opHash) {
            revert InvalidCallParameters();
        }

        // Check the guard before execution
        address guard = getGuard();
        bytes32 guardHash;
        if (guard != address(0)) {
            guardHash = IGuard(guard).checkTransactionFromModule(to, value, data, operation, module, opNonce);
        }

        // Set module execution before executing operation, then reset back to address(0x01) after finished.
        _setModuleExecution(module);
        _execute(to, value, data, operation);
        _setModuleExecution(MODULES_HEAD);

        // Check the guard after execution
        if (guard != address(0)) {
            IGuard(guard).checkAfterExecution(guardHash, true);
        }

        // Check that the operation status is still "ready" to protect against re-entrancy messing with the operation
        opStatus = _getOperationStatus(executableAt);
        if (opStatus != OperationStatus.Ready) {
            revert InvalidOperationStatus(opStatus, OperationStatus.Ready);
        }

        _op.executableAt = uint48(OperationStatus.Done);

        emit OperationExecuted(opNonce, module, to, value, data, operation);
    }

    function _setModuleExecution(address module) private {
        // TODO: Make this transient storage once it's available
        _getModuleExecutionStorage()._executingModule = module;
    }

    /// @inheritdoc ITimelockAvatar
    function cancelOperation(uint256 opNonce) external virtual {
        TimelockStorage storage $ = _getTimelockStorage();
        Operation storage _op = $._operations[opNonce];
        (address module, uint256 executableAt) = (_op.module, _op.executableAt);

        if (msg.sender != module) {
            revert UnauthorizedModule();
        }

        OperationStatus opStatus = _getOperationStatus(executableAt);
        if (opStatus != OperationStatus.Pending) {
            revert InvalidOperationStatus(opStatus, OperationStatus.Pending);
        }

        _op.executableAt = uint48(OperationStatus.Cancelled);

        emit OperationCancelled(opNonce, module);
    }

    /// @inheritdoc IAvatar
    function isModuleEnabled(address module) public view returns (bool enabled) {
        return module != MODULES_HEAD && _getTimelockStorage()._modules[module] != address(0);
    }

    /// @inheritdoc IAvatar
    function getModulesPaginated(
        address start,
        uint256 pageSize
    ) external view returns (
        address[] memory array,
        address next
    ) {
        TimelockStorage storage $ = _getTimelockStorage();

        // Check the start address and page size
        if (start != MODULES_HEAD && !isModuleEnabled(start)) {
            revert InvalidStartModule(start);
        }

        if (pageSize == 0) {
            revert InvalidPageSize(pageSize);
        }

        // Init array
        array = new address[](pageSize);

        // Init count and iterate through modules
        uint256 count = 0;
        next = $._modules[start];
        while(count < pageSize && next != MODULES_HEAD && next != address(0)) {
            array[count] = next;
            next = $._modules[next];
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

    /// @inheritdoc ITimelockAvatar
    function hashOperation(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    ) public pure virtual returns (bytes32 opHash) {
        opHash = keccak256(abi.encode(to, value, data, operation));
    }

    /// @dev An internal utility function to revert if the provided operation nonce does not exist
    function _checkOpNonce(TimelockStorage storage $, uint256 opNonce) internal view virtual {
        if (opNonce >= $._opNonce) {
            revert();
        }
    }

}