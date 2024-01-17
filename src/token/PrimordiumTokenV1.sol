// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {SharesToken} from "./base/SharesToken.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title PrimordiumTokenV1
 * @author Ben Jett - @BCJdevelopment
 * @notice The implementation contract for the first version of the Primordium shares token.
 */
contract PrimordiumTokenV1 is SharesToken, UUPSUpgradeable {
    struct TokenV1Init {
        address owner;
        string name;
        string symbol;
        SharesTokenInit sharesTokenInit;
    }

    constructor() {
        _disableInitializers();
    }

    function setUp(
        TokenV1Init memory init
    )
        public
        virtual
        initializer
    {
        __ERC20_init_unchained(init.name, init.symbol);
        __EIP712_init_unchained(init.name, "1");
        __Ownable_init_unchained(init.owner);
        __SharesToken_init_unchained(init.sharesTokenInit);
    }

    /// @dev Upgrading to new implementation is an only-owner operation
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}
