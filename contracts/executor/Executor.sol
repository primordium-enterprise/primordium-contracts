// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import "./base/Treasurer.sol";
import "contracts/utils/AuthorizeInitializer.sol";

/**
 * @title Executor - The deployable executor contract.
 *
 * @author Ben Jett - @BCJdevelopment
 */
abstract contract Executor is Initializable, AuthorizeInitializer, Treasurer {

    function initializeExecutor(
        bytes calldata params
    ) external initializer authorizeInitializer {

    }

}
