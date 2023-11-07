// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import "../executor/base/TimelockAvatar.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract TimelockAvatarControlled is Initializable {

    // The executor serves as the timelock and treasury
    TimelockAvatar internal _timelockAvatar;

    /**
     * @dev Emitted when the executor controller used for proposal execution is modified.
     */
    event ExecutorChange(address oldExecutor, address newExecutor);

    error OnlyExecutor(address executor);
    error InvalidExecutorAddress(address invalidAddress);
    error ExecutorNotInitialized();
    error ExecutorAlreadyInitialized();

    /// @dev Only the executor is allowed to execute these functions
    modifier onlyTimelockAvatar() {
        _onlyTimelockAvatar();
        _;
    }

    function _onlyTimelockAvatar() internal view {
        if (msg.sender != address(_timelockAvatar)) revert OnlyExecutor(address(_timelockAvatar));
    }

    /// @dev The executor must be initialized before these functions can be executed
    modifier avatarIsInitialized() {
        if (address(_timelockAvatar) == address(0)) revert ExecutorNotInitialized();
        _;
    }

    // Public view function for the executor
    function timelockAvatar() public view virtual returns(address) {
        return address(_timelockAvatar);
    }

    function __TimelockAvatarControlled_init(address timelockAvatar_) internal virtual onlyInitializing {
        if (address(_timelockAvatar) != address(0)) revert ExecutorAlreadyInitialized();
        _updateTimelockAvatar(timelockAvatar_);
    }

    /// @dev Internal function to update the Executor to a new address
    function _updateTimelockAvatar(address newExecutor) internal {
        if (newExecutor == address(0)) revert InvalidExecutorAddress(newExecutor);
        emit ExecutorChange(address(_timelockAvatar), newExecutor);
        _timelockAvatar = TimelockAvatar(payable(newExecutor));
    }

}