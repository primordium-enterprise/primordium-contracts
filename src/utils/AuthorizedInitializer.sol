// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title AuthorizeInitializer - A contract that allows setting an authorized address before initialization that only
 *
 * This contract stores the initializer in a ERC-7201 namespaced storage to avoid collisions.
 *
 * @notice This should NOT be used to ensure that an initializer runs only once. The "authorizeInitializer" modifier
 * will zero out the "initializer" address after successful initialization (which is equivalent to allowing anyone to
 * call the function going forward).
 *
 * @author Ben Jett - @BCJdevelopment
 */
abstract contract AuthorizedInitializer is Initializable {
    /// @custom:storage-location erc7201:AuthorizedInitializer.Storage
    struct AuthorizedInitializerStorage {
        address authorizedInitializer;
    }

    // keccak256(abi.encode(uint256(keccak256("AuthorizedInitializer.Storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant AUTHORIZED_INITIALIZER_STORAGE =
        0xc7a0cadad3d8ee736800300fdd3a44965ba070655c850f662dccfee2be552700;

    event InitializerAuthorized(address authorizedInitializer);

    error AlreadyInitialized();
    error AuthorizedInitializerAlreadySet();
    error UnauthorizedInitializer(address sender, address authorizedInitializer);

    /**
     * @dev Sets the authorized initializer. Requires that the contract has not been previously initialized, and that
     * the authorized initializer is not already set.
     */
    function setAuthorizedInitializer(address authorizedInitializer) public {
        // Revert if already initialized
        if (_getInitializedVersion() > 0) {
            revert AlreadyInitialized();
        }

        AuthorizedInitializerStorage storage $;
        assembly {
            $.slot := AUTHORIZED_INITIALIZER_STORAGE
        }

        if ($.authorizedInitializer != address(0)) {
            revert AuthorizedInitializerAlreadySet();
        }

        $.authorizedInitializer = authorizedInitializer;
        emit InitializerAuthorized(authorizedInitializer);
    }

    /**
     * @dev A modifier which authorizes that the msg.sender is the authorized initializer address, and reverts otherwise
     * (unless the authorized initializer is address(0)). Deletes the storage value after running the modified function,
     * preventing this from being used again.
     *
     * This modifier should be added to the initializer function to authorize the msg.sender on initialization.
     */
    modifier authorizeInitializer() {
        AuthorizedInitializerStorage storage $;
        assembly {
            $.slot := AUTHORIZED_INITIALIZER_STORAGE
        }
        address initializer = $.authorizedInitializer;
        // Require authorized initialization (address(0) means anyone can initialize)
        if (msg.sender != initializer && initializer != address(0)) {
            revert UnauthorizedInitializer(msg.sender, initializer);
        }
        _;
        // Clear the initializer for a refund (only used on initialization)
        delete $.authorizedInitializer;
    }
}
