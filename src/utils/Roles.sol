// SPDX-License-Identifier: MIT
// Primordium Contracts

import {RolesLib} from "../libraries/RolesLib.sol";

pragma solidity ^0.8.20;

/**
 * @title Roles
 * @author Ben Jett - @benbcjdev
 * @notice Some public boilerplate functions that make use of the {RolesLib} library for managing roles.
 */
contract Roles {
    /**
     * @dev Thrown when an account fails to confirm their own address when revoking their own role.
     */
    error UnauthorizedConfirmation();

    /**
     * @notice Returns true if the role is currently granted to the specified account.
     * @param role The bytes32 role hash.
     * @param account The account to be checked.
     */
    function hasRole(bytes32 role, address account) public view virtual returns (bool) {
        return RolesLib._hasRole(role, account);
    }

    /**
     * @notice Returns the timestamp that the role will expire at for the account.
     * @param role The bytes32 role hash.
     * @param account The account to be checked.
     */
    function roleExpiresAt(bytes32 role, address account) public view virtual returns (uint256) {
        return RolesLib._roleExpiresAt(role, account);
    }

    /**
     * @notice Allows a role holder to renounce their own role.
     * @param role The bytes32 role hash.
     * @param callerConfirmation The address of the msg.sender, as a confirmation to ensure the sender explicitly is
     * revoking their own role.
     */
    function renounceRole(bytes32 role, address callerConfirmation) public virtual {
        if (callerConfirmation != msg.sender) {
            revert UnauthorizedConfirmation();
        }

        RolesLib._revokeRole(role, callerConfirmation);
    }
}
