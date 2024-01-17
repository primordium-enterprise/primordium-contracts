// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import {BaseScriptV1, console2} from "./BaseV1.s.sol";
import {PrimordiumTokenV1} from "src/token/PrimordiumTokenV1.sol";
import {PrimordiumSharesOnboarderV1} from "src/onboarder/PrimordiumSharesOnboarderV1.sol";
import {PrimordiumGovernorV1} from "src/governor/PrimordiumGovernorV1.sol";
import {PrimordiumExecutorV1} from "src/executor/PrimordiumExecutorV1.sol";
import {DistributorV1} from "src/executor/extensions/DistributorV1.sol";

contract DeployImplementationsV1 is BaseScriptV1 {
    function run()
        public
        virtual
        broadcast
        returns (
            PrimordiumExecutorV1 executorImpl,
            PrimordiumTokenV1 tokenImpl,
            PrimordiumSharesOnboarderV1 sharesOnboarderImpl,
            PrimordiumGovernorV1 governorImpl,
            DistributorV1 distributorImpl
        )
    {
        return _deployAllImplementations();
    }
}
