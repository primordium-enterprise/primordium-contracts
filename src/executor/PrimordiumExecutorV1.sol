// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {Treasurer} from "./base/Treasurer.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title PrimordiumExecutorV1
 * @author Ben Jett - @BCJdevelopment
 * @notice The implementation contract for the first version of the Primordium executor.
 */
contract PrimordiumExecutorV1 is Treasurer, UUPSUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function setUp(
        bytes memory timelockAvatarInitParams,
        bytes memory treasurerInitParams
    )
        public
        virtual
        initializer
    {
        __TimelockAvatar_init(timelockAvatarInitParams);
        __Treasurer_init_unchained(treasurerInitParams);
    }

    /// @dev Only the executor itself can upgrade to a new implementation contract
    function _authorizeUpgrade(address newImplementation) internal virtual override onlySelf {}
}
