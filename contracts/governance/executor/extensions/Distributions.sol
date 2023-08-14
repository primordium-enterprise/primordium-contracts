// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.4;

import "./Treasurer.sol";
import "../../token/ERC20Checkpoints.sol";

contract Distributions {

    Treasurer private immutable _treasurer;
    ERC20Checkpoints private immutable _votes;

    constructor(
        Treasurer treasurer_,
        ERC20Checkpoints votes_
    ) {
        _treasurer = treasurer_;
        _votes = votes_;
    }



}