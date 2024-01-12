// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import {BaseV1Script, console2} from "./BaseV1.s.sol";
import {PrimordiumSharesTokenV1} from "src/token/PrimordiumSharesTokenV1.sol";
import {PrimordiumSharesOnboarderV1} from "src/onboarder/PrimordiumSharesOnboarderV1.sol";
import {PrimordiumGovernorV1} from "src/governor/PrimordiumGovernorV1.sol";
import {PrimordiumExecutorV1} from "src/executor/PrimordiumExecutorV1.sol";
import {DistributorV1} from "src/executor/extensions/DistributorV1.sol";

contract DeployV1Implementations is BaseV1Script {

    function run() public virtual broadcast {
        _deploy_implementation_SharesTokenV1();
        _deploy_implementation_SharesOnboarderV1();
        _deploy_implementation_GovernorV1();
        _deploy_implementation_ExecutorV1();
        _deploy_implementation_DistributorV1();
    }
}