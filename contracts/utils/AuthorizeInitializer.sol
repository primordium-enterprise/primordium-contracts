// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

/**
 * @title AuthorizeInitializer - A contract that takes an "initializer" address in the constructor, and includes an
 * "authorizeInitializer" modifier that can be used on a function to authorize that the msg.sender is the "initializer"
 * address. Using address(0) for the initializer allows anyone to initialize.
 *
 * This contract stores the initializer in a ERC-7201 namespaced storage to avoid collisions.
 *
 * @notice This should NOT be used to ensure that an initializer runs only once. The "authorizeInitializer" modifier
 * will zero out the "initializer" address after successful initialization (which is equivalent to allowing anyone to
 * call the function going forward).
 *
 * @author Ben Jett - @BCJdevelopment
 */
abstract contract AuthorizeInitializer {

    /**
     * @dev ERC-7201 storage of the initializer's address. Uses namespaced storage to avoid collisions.
     *
     * @custom:storage-location erc7201:AuthorizeInitializer.Initializer
     */
    struct Initializer {
        address initializer;
    }

    // keccak256(abi.encode(uint256(keccak256("AuthorizeInitializer.Initializer")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant INITIALIZER_STORAGE = 0x719278b5ce276eca957676c0e70eaee0aebe937c970dc4c35234416ee5d07700;

    event InitializerAuthorized(address authorizedInitializer);
    error UnauthorizedInitializer(address sender, address authorizedInitializer);

    constructor(address initializer) {
        Initializer storage $;
        assembly {
            $.slot := INITIALIZER_STORAGE
        }
        $.initializer = initializer;
        emit InitializerAuthorized(initializer);
    }

    /**
     * @dev A modifier which authorizes that the msg.sender is the "initializer" address, and reverts otherwise (unless
     * "initializer" has been set to address(0)).
     */
    modifier authorizeInitializer() {
        Initializer storage $;
        assembly {
            $.slot := INITIALIZER_STORAGE
        }
        address initializer = $.initializer;
        // Require authorized initialization (address(0) means anyone can initialize)
        if (msg.sender != initializer && initializer != address(0))
            revert UnauthorizedInitializer(msg.sender, initializer);
        _;
        // Clear the initializer for a refund (only used on initialization)
        delete $.initializer;
    }

}