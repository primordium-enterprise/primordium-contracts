// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {BatchArrayChecker} from "../utils/BatchArrayChecker.sol";

/**
 * @title RolesLib
 * @author Ben Jett - @BCJdevelopment
 * @notice A library with logic functions for managing and checking roles for various accounts.
 * @dev This library stores it's internal state at erc7201:RolesLib.Storage.
 */
library RolesLib {
    /// @custom:storage-location erc7201:RolesLib.Storage
    struct RolesLibStorage {
        mapping(bytes32 role => mapping(address account => uint256 roleExpiresAt)) _roleMembers;
    }

    // keccak256(abi.encode(uint256(keccak256("RolesLib.Storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant ROLES_LIB_STORAGE = 0xe6af496e06be4eb3a912ed0411bab2b251945059ba94a68f0c32215f80cf7100;

    function _getRolesLibStorage() private pure returns (RolesLibStorage storage $) {
        assembly {
            $.slot := ROLES_LIB_STORAGE
        }
    }

    /**
     * @dev Emitted when a role has been granted.
     * @param role The bytes32 role granted.
     * @param account The account the role was granted to.
     * @param expiresAt A timestamp at which the role will expire.
     */
    event RoleGranted(bytes32 role, address account, uint256 expiresAt);

    /**
     * @dev Emitted when a role has been revoked.
     * @param role The bytes32 role revoked.
     * @param account The account the role was revoked from.
     */
    event RoleRevoked(bytes32 role, address account);

    /**
     * @dev Thrown when an account does not possess the required role.
     */
    error UnauthorizedRole(bytes32 role, address account);

    /**
     * @dev Thrown when an account does not possess any of the required roles.
     */
    error UnauthorizedRoles(bytes32[] roles, address account);

    /**
     * @dev An internal utility to check the role of the specified account, reverts if the account does not currently
     * carry the role.
     * @param role The bytes32 role hash.
     * @param account The account to check.
     */
    function _checkRole(bytes32 role, address account) internal view {
        if (!_hasRole(role, account)) {
            revert UnauthorizedRole(role, account);
        }
    }

    /**
     * @dev An internal utility to check that the account carries at least one of the specified roles, reverts if the
     * account does not currently carry any of the provided roles.
     * @param roles The bytes32 role hashes.
     * @param account The account to check.
     */
    function _checkRoles(bytes32[] memory roles, address account) internal view {
        if (!_hasRoles(roles, account)) {
            revert UnauthorizedRoles(roles, account);
        }
    }

    /**
     * @dev Internal utility to see whether or not an account has a specified role.
     * @param role The bytes32 role hash.
     * @param account The account to be checked.
     * @return hasRole True if the account currently carries the specified role.
     */
    function _hasRole(bytes32 role, address account) internal view returns (bool hasRole) {
        hasRole = _getRolesLibStorage()._roleMembers[role][account] > block.timestamp;
    }

    /**
     * @dev Internal utility to see whether or not an account has a specified role.
     * @param roles The bytes32 role hashes.
     * @param account The account to be checked.
     * @return hasRole True if the account currently carries at least one of the specified roles.
     */
    function _hasRoles(bytes32[] memory roles, address account) internal view returns (bool hasRole) {
        RolesLibStorage storage $ = _getRolesLibStorage();
        for (uint256 i = 0; i < roles.length;) {
            if ($._roleMembers[roles[i]][account] > block.timestamp) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Returns the timestamp that the role will expire at for the account.
     * @param role The bytes32 role hash.
     * @param account The account to be checked.
     */
    function _roleExpiresAt(bytes32 role, address account) internal view returns (uint256 expiresAt) {
        expiresAt = _getRolesLibStorage()._roleMembers[role][account];
    }

    /**
     * @dev Internal utility to grant a role to an account indefinitely.
     */
    function _grantRole(bytes32 role, address account) internal {
        _grantRole(role, account, type(uint256).max);
    }

    /**
     * @dev Internal utility to grant a role to an account up until the provided expiresAt timestamp.
     */
    function _grantRole(bytes32 role, address account, uint256 expiresAt) internal {
        _grantRole(_getRolesLibStorage(), role, account, expiresAt);
    }

    /**
     * @dev Internal utility to grant a role to an account up until the provided expiresAt timestamp.
     */
    function _grantRole(RolesLibStorage storage $, bytes32 role, address account, uint256 expiresAt) internal {
        $._roleMembers[role][account] = expiresAt;
        emit RoleGranted(role, account, expiresAt);
    }

    /**
     * @dev Batch method for granting roles.
     */
    function _grantRoles(bytes32[] memory roles, address[] memory accounts, uint256[] memory expiresAts) internal {
        BatchArrayChecker.checkArrayLengths(roles.length, accounts.length, expiresAts.length);

        RolesLibStorage storage $ = _getRolesLibStorage();
        for (uint256 i = 0; i < roles.length;) {
            _grantRole($, roles[i], accounts[i], expiresAts[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Internal utility to revoke the role for the specified account.
     */
    function _revokeRole(bytes32 role, address account) internal {
        _revokeRole(_getRolesLibStorage(), role, account);
    }

    /**
     * @dev Internal utility to revoke the role for the specified account.
     */
    function _revokeRole(RolesLibStorage storage $, bytes32 role, address account) internal {
        if (_hasRole(role, account)) {
            delete $._roleMembers[role][account];
            emit RoleRevoked(role, account);
        }
    }

    /**
     * @dev Batch method for revoking roles.
     */
    function _revokeRoles(bytes32[] memory roles, address[] memory accounts) internal {
        BatchArrayChecker.checkArrayLengths(roles.length, accounts.length);

        RolesLibStorage storage $ = _getRolesLibStorage();
        for (uint256 i = 0; i < roles.length;) {
            _revokeRole($, roles[i], accounts[i]);
            unchecked {
                ++i;
            }
        }
    }
}
