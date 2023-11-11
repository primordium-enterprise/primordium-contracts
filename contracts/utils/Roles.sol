// SPDX-License-Identifier: MIT
// Primordium Contracts

import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

pragma solidity ^0.8.20;

contract Roles is ContextUpgradeable {

    mapping(bytes32 => mapping(address => uint256)) internal _roleMembers;

    event RoleGranted(bytes32 role, address account, uint256 expiresAt);
    event RoleRevoked(bytes32 role, address account);

    error MismatchingBatchLengths();
    error UnauthorizedRole(bytes32 role, address account);

    /**
     * @dev Modifier to revert if the msg.sender does not have the specified role.
     */
    modifier onlyRole(bytes32 role) {
        _checkRole(role);
        _;
    }

    /**
     * @notice Returns true if the role is currently granted to the specified account.
     * @param role The bytes32 role hash.
     * @param account The account to be checked.
     */
    function hasRole(bytes32 role, address account) public view virtual returns (bool) {
        return _hasRole(role, account);
    }

    /**
     * @notice Returns the timestamp that the role will expire at for the account.
     * @param role The bytes32 role hash.
     * @param account The account to be checked.
     */
    function roleExpiresAt(bytes32 role, address account) public view virtual returns (uint256) {
        return _roleMembers[role][account];
    }

    /**
     * @dev Internal utility to see whether or not an account has a specified role.
     */
    function _hasRole(bytes32 role, address account) internal view virtual returns (bool) {
        return _roleMembers[role][account] > block.timestamp;
    }

    /**
     * @dev An internal utility to check the role of the msg.sender, reverts if the role is not granted.
     */
    function _checkRole(bytes32 role) internal view virtual {
        _checkRole(role, _msgSender());
    }

    /**
     * @dev An internal utility to check the role of the specified account, reverts if the role is not granted.
     */
    function _checkRole(bytes32 role, address account) internal view virtual {
        if (!_hasRole(role, account)) {
            revert UnauthorizedRole(role, account);
        }
    }

    /**
     * @dev Internal utility to grant a role to an account indefinitely.
     */
    function _grantRole(bytes32 role, address account) internal virtual {
        _grantRole(role, account, type(uint256).max);
    }

    /**
     * @dev Internal utility to grant a role to an account up until the provided expiresAt timestamp.
     */
    function _grantRole(bytes32 role, address account, uint256 expiresAt) internal virtual {
        _roleMembers[role][account] = expiresAt;
        emit RoleGranted(role, account, expiresAt);
    }

    /**
     * @dev Batch method for granting roles.
     */
    function _grantRolesBatch(
        bytes32[] calldata roles,
        address[] calldata accounts,
        uint256[] calldata expiresAts
    ) internal virtual {
        if (
            roles.length == 0 ||
            roles.length != accounts.length ||
            roles.length != expiresAts.length
        ) revert MismatchingBatchLengths();
        for (uint256 i = 0; i < roles.length;) {
            _grantRole(roles[i], accounts[i], expiresAts[i]);
            unchecked { ++i; }
        }
    }

    /**
     * @dev Internal utility to revoke the role for the specified account.
     */
    function _revokeRole(bytes32 role, address account) internal virtual {
        if (hasRole(role, account)) {
            delete _roleMembers[role][account];
            emit RoleRevoked(role, account);
        }
    }

    /**
     * @dev Batch method for revoking roles.
     */
    function _revokeRolesBatch(
        bytes32[] calldata roles,
        address[] calldata accounts
    ) internal virtual {
        if (
            roles.length == 0 ||
            roles.length != accounts.length
        ) revert MismatchingBatchLengths();
        for (uint256 i = 0; i < roles.length;) {
            _revokeRole(roles[i], accounts[i]);
            unchecked { ++i; }
        }
    }

}