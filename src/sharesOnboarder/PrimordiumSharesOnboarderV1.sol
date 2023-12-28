// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {SharesOnboarder} from "./base/SharesOnboarder.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

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
