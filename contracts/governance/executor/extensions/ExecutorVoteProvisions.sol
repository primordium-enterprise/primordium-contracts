// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "../../token/extensions/VotesProvisioner.sol";
import "../Executor.sol";

abstract contract ExecutorVoteProvisions is Executor {

    VotesProvisioner internal immutable _votes;

    constructor(
        VotesProvisioner votes_
    ) {
        _votes = votes_;
    }

    function votes() public view returns(address) {
        return address(_votes);
    }

}