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
    struct GovernorV1Init {
        string name;
        GovernorBaseInit governorBaseInit;
        ProposalVotingInit proposalVotingInit;
        ProposalDeadlineExtensionsInit proposalDeadlineExtensionsInit;
    }

    constructor() {
        _disableInitializers();
    }

    function setUp(
        GovernorV1Init memory init
    )
        public
        virtual
        initializer
    {
        __EIP712_init_unchained(init.name, version());
        __GovernorBase_init_unchained(init.governorBaseInit);
        __ProposalVoting_init_unchained(init.proposalVotingInit);
        __ProposalDeadlineExtensions_init_unchained(init.proposalDeadlineExtensionsInit);
    }

    /// @dev Upgrading to new implementation is an only-governance operation
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyGovernance {}
}
