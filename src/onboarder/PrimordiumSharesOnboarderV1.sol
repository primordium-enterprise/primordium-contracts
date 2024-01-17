// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {SharesOnboarder} from "./base/SharesOnboarder.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title PrimordiumSharesOnboarderV1
 * @author Ben Jett - @BCJdevelopment
 * @notice The implementation contract for the first version of the Primordium shares onboarder.
 */
contract PrimordiumSharesOnboarderV1 is SharesOnboarder, UUPSUpgradeable {
    struct SharesOnboarderV1Init {
        address owner;
        SharesOnboarderInit sharesOnboarderInit;
    }

    constructor() {
        _disableInitializers();
    }

    function setUp(SharesOnboarderV1Init memory init) public virtual initializer {
        __Ownable_init_unchained(init.owner);
        __SharesOnboarder_init_unchained(init.sharesOnboarderInit);
    }

    /// @dev Upgrading to new implementation is an only-owner operation
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}
