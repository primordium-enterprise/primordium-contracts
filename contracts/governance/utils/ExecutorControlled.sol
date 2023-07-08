// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "../Executor.sol";
import "@openzeppelin/contracts/utils/Context.sol";

abstract contract IExecutorControlled {

    /**
     * @dev Emitted when the executor controller used for proposal execution is modified.
     */
    event ExecutorChange(address oldExecutor, address newExecutor);

    /**
     * @dev Returns address for executor contract
     */
    function executor() public view virtual returns(address);

}

abstract contract ExecutorControlled is Context, IExecutorControlled {

    constructor(
        Executor executor_
    ) {
        _updateExecutor(executor_);
    }

    // Executor serves as the timelock and treasury
    Executor internal _executor;

    // Public view function for the executor
    function executor() public view virtual override returns(address) {
        return address(_executor);
    }

    function _updateExecutor(Executor newExecutor) internal {
        // If the _executor has already been initialized at some point, don't let it go back to zero address.
        if (address(_executor) != address(0)) {
            require(address(newExecutor) != address(0), "ExecutorControlled: cannot set executor to address(0).");
        }
        emit ExecutorChange(address(_executor), address(newExecutor));
        _executor = newExecutor;
    }

    modifier onlyExecutor() {
        require(_msgSender() == address(_executor), "ExecutorControlled: onlyExecutor");
        _;
    }

    /**
     * @dev A helpful extension for initializing the ExecutorControlled contract when deploying the first version
     *
     * 1. Deploy Executor (deployer address as the owner)
     * 2. Deploy ExecutorControlled contract with _executor address set to address(0)
     * 3. Call {initializeExecutor} from deployer address (to set the _executor and complete the ownership transfer)
     */
    function initializeExecutor(Executor newExecutor) public virtual {
        require(executor() == address(0), "ExecutorControlled: Can only initialize executor once.");
        require(
            newExecutor.owner() == _msgSender(),
            "ExecutorControlled: Call must come from the current owner of the _executor."
        );
        _updateExecutor(newExecutor);
    }

}