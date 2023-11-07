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
    event TimelockAvatarChange(address oldTimelockAvatar, address newTimelockAvatar);

    error OnlyTimelockAvatar(address timelockAvatar);
    error InvalidTimelockAvatarAddress(address invalidAddress);
    error TimelockAvatarNotInitialized();
    error TimelockAvatarAlreadyInitialized();

    /// @dev Only the executor is allowed to execute these functions
    modifier onlyTimelockAvatar() {
        _onlyTimelockAvatar();
        _;
    }

    function _onlyTimelockAvatar() internal view {
        if (msg.sender != address(_timelockAvatar)) revert OnlyTimelockAvatar(address(_timelockAvatar));
    }

    /// @dev The executor must be initialized before these functions can be executed
    modifier avatarIsInitialized() {
        if (address(_timelockAvatar) == address(0)) revert TimelockAvatarNotInitialized();
        _;
    }

    // Public view function for the executor
    function timelockAvatar() public view virtual returns(address) {
        return address(_timelockAvatar);
    }

    function __TimelockAvatarControlled_init(address timelockAvatar_) internal virtual onlyInitializing {
        if (address(_timelockAvatar) != address(0)) revert TimelockAvatarAlreadyInitialized();
        _updateTimelockAvatar(timelockAvatar_);
    }

    /// @dev Internal function to update the Executor to a new address. Does not allow setting to itself.
    function _updateTimelockAvatar(address timelockAvatar_) internal {
        if (
            timelockAvatar_ == address(0) || timelockAvatar_ == address(this)
        ) revert InvalidTimelockAvatarAddress(timelockAvatar_);

        emit TimelockAvatarChange(address(_timelockAvatar), timelockAvatar_);
        _timelockAvatar = TimelockAvatar(payable(timelockAvatar_));
    }

}