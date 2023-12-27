// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {GovernorSettingsRanges} from "./helpers/GovernorSettingsRanges.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title PrimordiumGovernorV1
 * @author Ben Jett - @BCJdevelopment
 * @notice The implementation contract for the first version of the Primordium Governor.
 */
contract PrimordiumGovernorV1 is GovernorSettingsRanges, UUPSUpgradeable {
    constructor() {
        _disableInitializers();
    }

    function setUp(
        bytes memory governorBaseInitParams,
        bytes memory proposalsInitParams,
        bytes memory proposalVotingInitParams,
        bytes memory proposalDeadlineExtensionsInitParams
    ) external initializer {
        __GovernorBase_init(governorBaseInitParams);
        __Proposals_init_unchained(proposalsInitParams);
        __ProposalVoting_init_unchained(proposalVotingInitParams);
        __ProposalDeadlineExtensions_init_unchained(proposalDeadlineExtensionsInitParams);
    }

    /// @dev Upgrading to new implementation is an only-governance operation
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyGovernance {}
}
