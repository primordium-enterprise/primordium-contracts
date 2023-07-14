// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "./governance/executor/extensions/Treasurer.sol";

contract PrimordiumExecutor is Executor, Treasurer {

    constructor(
        uint256 minDelay,
        address owner,
        VotesProvisioner votes_
    ) Executor(minDelay, owner) Treasurer(votes_) {

    }


}