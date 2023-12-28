// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {SharesToken} from "./base/SharesToken.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title PrimordiumSharesTokenV1
 * @author Ben Jett - @BCJdevelopment
 * @notice The implementation contract for the first version of the Primordium shares token.
 */
contract PrimordiumSharesTokenV1 is SharesToken, UUPSUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function setUp(
        address owner_,
        string memory name,
        string memory symbol,
        bytes memory sharesTokenInitParams
    )
        external
        initializer
    {
        __ERC20_init_unchained(name, symbol);
        __EIP712_init_unchained(name, "1");
        __Ownable_init_unchained(owner_);
        __SharesToken_init_unchained(sharesTokenInitParams);
    }

    /// @dev Upgrading to new implementation is an only-owner operation
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}
