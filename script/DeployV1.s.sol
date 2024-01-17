// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import {BaseScriptV1, console2} from "./BaseV1.s.sol";
import {PrimordiumDAOConfigV1} from "./config/PrimordiumDAOConfigV1.sol";
import {DeployImplementationsV1} from "./DeployImplementationsV1.s.sol";
import {DeployAndSetUpProxiesV1} from "./DeployAndSetUpProxiesV1.s.sol";
import {PrimordiumTokenV1} from "src/token/PrimordiumTokenV1.sol";
import {PrimordiumSharesOnboarderV1} from "src/onboarder/PrimordiumSharesOnboarderV1.sol";
import {PrimordiumGovernorV1} from "src/governor/PrimordiumGovernorV1.sol";
import {PrimordiumExecutorV1} from "src/executor/PrimordiumExecutorV1.sol";
import {DistributorV1} from "src/executor/extensions/DistributorV1.sol";

contract DeployV1 is BaseScriptV1, PrimordiumDAOConfigV1 {
    struct Implementations {
        PrimordiumExecutorV1 executorImpl;
        PrimordiumTokenV1 tokenImpl;
        PrimordiumSharesOnboarderV1 sharesOnboarderImpl;
        PrimordiumGovernorV1 governorImpl;
        DistributorV1 distributorImpl;
    }

    struct Proxies {
        PrimordiumExecutorV1 executor;
        PrimordiumTokenV1 token;
        PrimordiumSharesOnboarderV1 sharesOnboarder;
        PrimordiumGovernorV1 governor;
    }

    function run() public virtual broadcast returns (Implementations memory i, Proxies memory p) {
        // Implementations
        (i.executorImpl, i.tokenImpl, i.sharesOnboarderImpl, i.governorImpl, i.distributorImpl) =
            _deployAllImplementations();

        // Proxies
        (p.executor, p.token, p.sharesOnboarder, p.governor) = _deployAndSetupAllProxies();
    }
}
