// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {GovernorBase} from "./GovernorBase.sol";
import {Treasurer} from "contracts/executor/base/Treasurer.sol";

/**
 * @title GovernanceInitialization
 *
 * @dev Initialized deposits on the Executor once the governance operations are initialized on the Governor.
 *
 * @author Ben Jett - @BCJdevelopment
 */
abstract contract GovernanceInitialization is GovernorBase {

    /**
     * @dev Overrides to additionally initialize deposits on the Treasurer contract.
     */
    function _initializeGovernance() internal virtual override {
        super._initializeGovernance();
        Treasurer(payable(address(executor()))).initializeDeposits();
    }

}