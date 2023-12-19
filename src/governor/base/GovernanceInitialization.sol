// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {GovernorBase} from "./GovernorBase.sol";
import {Treasurer} from "src/executor/base/Treasurer.sol";

/**
 * @title GovernanceInitialization
 *
 * @dev Initialized deposits on the Executor once the governance operations are initialized on the Governor.
 *
 * @author Ben Jett - @BCJdevelopment
 */
abstract contract GovernanceInitialization is GovernorBase {
    /**
     * @dev Overrides to additionally try initializing deposits on the Treasurer contract.
     */
    function _initializeGovernance(uint256 proposalId) internal virtual override {
        super._initializeGovernance(proposalId);
        try Treasurer(payable(address(executor()))).enableBalanceShares(true) {} catch {}
    }
}
