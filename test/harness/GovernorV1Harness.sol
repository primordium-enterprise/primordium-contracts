// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {PrimordiumGovernorV1} from "src/governor/PrimordiumGovernorV1.sol";
import {GovernorBaseLogicV1} from "src/governor/base/logic/GovernorBaseLogicV1.sol";

contract GovernorV1Harness is PrimordiumGovernorV1 {
    function harnessFoundGovernor() public {
        GovernorBaseLogicV1._getGovernorBaseStorage()._isFounded = true;
    }
}