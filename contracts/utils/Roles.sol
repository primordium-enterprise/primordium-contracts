// SPDX-License-Identifier: MIT
// Primordium Contracts

import "@openzeppelin/contracts/utils/Context.sol";

pragma solidity ^0.8.4;

contract Roles is Context {

    mapping(bytes32 => mapping(address => uint256)) _roleMembers;

    event RoleGranted(bytes32 role, address account, uint256 expiresAt);
    event RoleRevoked(bytes32 role, address account);

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
        return _roleMembers[role][account] > block.timestamp;
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
     * @dev An internal utility to check the role of the msg.sender, reverts if the role is not granted.
     */
    function _checkRole(bytes32 role) internal view virtual {
        _checkRole(role, _msgSender());
    }

    /**
     * @dev An internal utility to check the role of the specified account, reverts if the role is not granted.
     */
    function _checkRole(bytes32 role, address account) internal view virtual {
        if (_roleMembers[role][account] <= block.timestamp) {
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
     * @dev Internal utility to revoke the role for the specified account.
     */
    function _revokeRole(bytes32 role, address account) internal virtual {
        if (hasRole(role, account)) {
            delete _roleMembers[role][account];
            emit RoleRevoked(role, account);
        }
    }

}