// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

abstract contract SelfAuthorized {

    error OnlySelfAuthorized();

    /**
     * @dev Modifier to make a function callable only by this contract itself.
     */
    modifier onlySelf {
        _onlySelf();
        _;
    }

    function _onlySelf() internal view {
        if (msg.sender != address(this)) {
            revert OnlySelfAuthorized();
        }
    }

}