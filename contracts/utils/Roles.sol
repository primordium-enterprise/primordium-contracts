// SPDX-License-Identifier: MIT
// Primordium Contracts

import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

pragma solidity ^0.8.20;

contract Roles is ContextUpgradeable {
    /// @custom:storage-location erc7201:Roles.Storage
    struct RolesStorage {
        mapping(bytes32 => mapping(address => uint256)) _roleMembers;
    }

    // keccak256(abi.encode(uint256(keccak256("Roles.Storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant ROLES_STORAGE = 0x178df759d714130ff191f7d05a0c43c12b5f4a8bdb6035ff61b650fdfd384b00;

    function _getRolesStorage() private pure returns (RolesStorage storage $) {
        assembly {
            $.slot := ROLES_STORAGE
        }
    }

    event RoleGranted(bytes32 role, address account, uint256 expiresAt);
    event RoleRevoked(bytes32 role, address account);

    error MismatchingBatchLengths();
    error UnauthorizedRole(bytes32 role, address account);
    error Unauthorized();

    /**
     * @dev Modifier to revert if the msg.sender does not have the specified role.
     */
    modifier onlyRole(bytes32 role) {
        _checkRole(role);
        _;
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
        return _getRolesStorage()._roleMembers[role][account];
    }

    /**
     * @dev Internal utility to see whether or not an account has a specified role.
     */
    function _hasRole(bytes32 role, address account) internal view virtual returns (bool) {
        return _getRolesStorage()._roleMembers[role][account] > block.timestamp;
    }

    /**
     * @dev An internal utility to check the role of the msg.sender, reverts if the role is not granted.
     */
    function _checkRole(bytes32 role) internal view virtual {
        _checkRole(role, _msgSender());
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
        _getRolesStorage()._roleMembers[role][account] = expiresAt;
        emit RoleGranted(role, account, expiresAt);
    }

    /**
     * @dev Batch method for granting roles.
     */
    function _grantRoles(
        bytes32[] memory roles,
        address[] memory accounts,
        uint256[] memory expiresAts
    )
        internal
        virtual
    {
        // forgefmt: disable-next-item
        if (
            roles.length == 0 ||
            roles.length != accounts.length ||
            roles.length != expiresAts.length
        ) {
            revert MismatchingBatchLengths();
        }

        for (uint256 i = 0; i < roles.length;) {
            _grantRole(roles[i], accounts[i], expiresAts[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * Allows a role holder to renounce their own role.
     */
    function renounceRole(bytes32 role, address callerConfirmation) public virtual {
        if (callerConfirmation != msg.sender) {
            revert Unauthorized();
        }

        _revokeRole(role, callerConfirmation);
    }

    /**
     * @dev Internal utility to revoke the role for the specified account.
     */
    function _revokeRole(bytes32 role, address account) internal virtual {
        if (_hasRole(role, account)) {
            delete _getRolesStorage()._roleMembers[role][account];
            emit RoleRevoked(role, account);
        }
    }

    /**
     * @dev Batch method for revoking roles.
     */
    function _revokeRoles(bytes32[] memory roles, address[] memory accounts) internal virtual {
        if (roles.length == 0 || roles.length != accounts.length) {
            revert MismatchingBatchLengths();
        }

        for (uint256 i = 0; i < roles.length;) {
            _revokeRole(roles[i], accounts[i]);
            unchecked {
                ++i;
            }
        }
    }
}
