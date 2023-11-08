// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

contract AuthorizeInitializer {

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

    modifier checkInitializer() {
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