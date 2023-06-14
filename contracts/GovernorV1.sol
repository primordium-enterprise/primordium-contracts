// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "./governance/governor/Governor.sol";
import "./governance/governor/extensions/GovernorVotes.sol";

contract GovernorV1 is Governor, GovernorVotes {

    function name() public pure override returns (string memory) {
        return "Primordium Governor";
    }

}
