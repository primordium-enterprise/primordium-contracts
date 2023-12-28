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
    constructor() {
        _disableInitializers();
    }

    function setUp(address owner_, bytes memory sharesOnboarderInitParams) external initializer {
        __Ownable_init_unchained(owner_);
        __SharesOnboarder_init_unchained(sharesOnboarderInitParams);
    }

    /// @dev Upgrading to new implementation is an only-owner operation
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}
