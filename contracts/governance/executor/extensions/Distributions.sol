// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.4;

import "./Treasurer.sol";

contract Distributions {

    Treasurer private immutable _treasurer;
    VotesProvisioner private immutable _votes;

    constructor(
        Treasurer treasurer_,
        VotesProvisioner votes_
    ) {
        _treasurer = treasurer_;
        _votes = votes_;
    }

}