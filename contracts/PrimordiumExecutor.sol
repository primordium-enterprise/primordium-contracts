// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "./governance/executor/extensions/ExecutorVoteProvisions.sol";

contract PrimordiumExecutor is Executor, ExecutorVoteProvisions {

    constructor(
        uint256 minDelay,
        address owner,
        VotesProvisioner votes_
    ) Executor(minDelay, owner) ExecutorVoteProvisions(votes_) {

    }


}