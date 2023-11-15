// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {TimelockAvatar} from "contracts/executor/base/TimelockAvatar.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";

/**
 * @title TimelockAvatarControlled
 *
 * @notice Is a parent contract to the GovernorBase module. This contract houses the executor logic for the Governor to
 * use the TimelockAvatar base contract as an executor for all of it's operations.
 *
 * @author Ben Jett - @BCJdevelopment
 */
abstract contract TimelockAvatarControlled is Initializable, ContextUpgradeable {
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    /// @custom:storage-location erc7201:TimelockAvatarControlled.Storage
    struct TimelockStorage {
        // This queue keeps track of the governor operating on itself. Calls to functions protected by the
        // {onlyGovernance} modifier needs to be whitelisted in this queue. Whitelisting is set in {execute}, consumed
        // by the {onlyGovernance} modifier and eventually reset after {_executeOperations} is complete. This ensures
        // that the execution of {onlyGovernance} protected calls can only be achieved through successful proposals.
        DoubleEndedQueue.Bytes32Deque _governanceCall;

        // The executor serves as the timelock and treasury
        TimelockAvatar _executor;
    }

    bytes32 private immutable TIMELOCK_STORAGE =
        keccak256(abi.encode(uint256(keccak256("TimelockAvatarControlled.Storage")) - 1)) & ~bytes32(uint256(0xff));

    function _getTimelockStorage() private view returns (TimelockStorage storage $) {
        bytes32 timelockStorageSlot = TIMELOCK_STORAGE;
        assembly {
            $.slot := timelockStorageSlot
        }
    }

    /**
     * @dev Emitted when the executor controller used for proposal execution is modified.
     */
    event TimelockAvatarChange(address oldTimelockAvatar, address newTimelockAvatar);

    error OnlyGovernance();
    error InvalidTimelockAvatarAddress(address invalidAddress);
    error TimelockAvatarAlreadyInitialized();

    /**
     * @dev Restricts a function so it can only be executed through governance proposals. For example, governance
     * parameter setters in {GovernorSettings} are protected using this modifier.
     */
    modifier onlyGovernance() {
        _onlyGovernance();
        _;
    }

    function _onlyGovernance() private {
        TimelockStorage storage $ = _getTimelockStorage();
        address executor_ = address(executor());
        if (msg.sender != executor_) revert OnlyGovernance();
        bytes32 msgDataHash = keccak256(_msgData());
        // loop until popping the expected operation - throw if deque is empty (operation not authorized)
        while ($._governanceCall.popFront() != msgDataHash) {}
    }

    /**
     * @dev TimelockAvatarControlled upgradeable initialization function.
     */
    function __TimelockAvatarControlled_init(address executor_) internal virtual onlyInitializing {
        if (address(executor()) != address(0)) revert TimelockAvatarAlreadyInitialized();
        _updateExecutor(executor_);
    }

    /**
     * @dev Get the governance call dequeuer for governance operations.
     */
    function _getGovernanceCallQueue() internal view returns (DoubleEndedQueue.Bytes32Deque storage governanceCall) {
        governanceCall = _getTimelockStorage()._governanceCall;
    }

    /**
     * Returns the address of the executor.
     */
    function executor() public view virtual returns (TimelockAvatar) {
        TimelockStorage storage $ = _getTimelockStorage();
        return $._executor;
    }

    /**
     * @dev Public endpoint to update the underlying timelock instance. Restricted to the timelock itself, so updates
     * must be proposed, scheduled, and executed through governance proposals.
     *
     * CAUTION: It is not recommended to change the timelock while there are other queued governance proposals.
     */
    function updateExecutor(address newExecutor) external onlyGovernance {
        _updateExecutor(newExecutor);
    }

    /// @dev Internal function to update the Executor to a new address. Does not allow setting to itself.
    function _updateExecutor(address executor_) internal {
        if (
            executor_ == address(0) || executor_ == address(this)
        ) revert InvalidTimelockAvatarAddress(executor_);

        TimelockStorage storage $ = _getTimelockStorage();

        emit TimelockAvatarChange(address($._executor), executor_);
        $._executor = TimelockAvatar(payable(executor_));
    }

}