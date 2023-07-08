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

    // Executor serves as the timelock and treasury
    Executor internal _executor;

    // Public view function for the executor
    function executor() public view virtual override returns(address) {
        return address(_executor);
    }

    function _updateExecutor(Executor newExecutor) internal {
        emit ExecutorChange(address(_executor), address(newExecutor));
        _executor = newExecutor;
    }

    modifier onlyExecutor() {
        require(_msgSender() == address(_executor), "ExecutorControlled: onlyExecutor");
        _;
    }

}