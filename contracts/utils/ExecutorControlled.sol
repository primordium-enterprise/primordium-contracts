// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "../executor/Executor.sol";

abstract contract ExecutorControlled {

    // Executor serves as the timelock and treasury
    Executor internal _executor;

    /**
     * @dev Emitted when the executor controller used for proposal execution is modified.
     */
    event ExecutorChange(address oldExecutor, address newExecutor);

    error OnlyExecutor(address executor);
    error InvalidExecutorAddress(address invalidAddress);
    error ExecutorNotInitialized();
    error ExecutorInitializesOnlyOnce();
    error NewExecutorOwnerMustInitialize(address newExecutorOwner);

    /// @dev Only the executor is allowed to execute these functions
    modifier onlyExecutor() {
        _onlyExecutor();
        _;
    }

    /// @dev The executor must be initialized before these functions can be executed
    modifier executorIsInitialized() {
        if (address(_executor) == address(0)) revert ExecutorNotInitialized();
        _;
    }

    constructor(
        Executor executor_
    ) {
        _updateExecutor(executor_);
    }

    // Public view function for the executor
    function executor() public view virtual returns(address) {
        return address(_executor);
    }

    /**
     * @dev A helpful extension for initializing the ExecutorControlled contract when deploying the first version
     *
     * 1. Deploy Executor (deployer address as the owner)
     * 2. Deploy ExecutorControlled contract with _executor address set to address(0)
     * 3. Call {initializeExecutor} from deployer address (to set the _executor and complete the ownership transfer)
     */
    function initializeExecutor(Executor newExecutor) public virtual {
        if (address(_executor) != address(0)) revert ExecutorInitializesOnlyOnce();
        if (newExecutor.owner() != msg.sender) revert NewExecutorOwnerMustInitialize(newExecutor.owner());
        _updateExecutor(newExecutor);
    }

    /// @dev Internal function to update the Executor to a new address
    function _updateExecutor(Executor newExecutor) internal {
        // If the _executor has already been initialized at some point, don't let it go back to zero address.
        if (address(_executor) != address(0)) {
            if (address(newExecutor) == address(0)) revert InvalidExecutorAddress(address(newExecutor));
        }
        emit ExecutorChange(address(_executor), address(newExecutor));
        _executor = newExecutor;
    }

    function _onlyExecutor() internal view {
        if (msg.sender != address(_executor)) revert OnlyExecutor(address(_executor));
    }

}