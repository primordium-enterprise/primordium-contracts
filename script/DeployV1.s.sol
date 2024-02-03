// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import {BaseScriptV1, console2} from "./BaseV1.s.sol";
import {PrimordiumV1} from "./PrimordiumV1.sol";
import {PrimordiumTokenV1} from "src/token/PrimordiumTokenV1.sol";
import {PrimordiumSharesOnboarderV1} from "src/onboarder/PrimordiumSharesOnboarderV1.sol";
import {PrimordiumGovernorV1} from "src/governor/PrimordiumGovernorV1.sol";
import {PrimordiumExecutorV1} from "src/executor/PrimordiumExecutorV1.sol";
import {DistributorV1} from "src/executor/extensions/DistributorV1.sol";

contract DeployV1 is BaseScriptV1, PrimordiumV1 {
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

    function run()
        public
        virtual
        broadcast
        returns (bytes32 saltImplementations, Implementations memory i, bytes32 saltProxies, Proxies memory p)
    {
        // Implementations
        saltImplementations = deploySaltImplementation;
        (i.executorImpl, i.tokenImpl, i.sharesOnboarderImpl, i.governorImpl, i.distributorImpl) =
            _deployAllImplementations();

        // Proxies
        saltProxies = deploySaltProxy;
        (p.executor, p.token, p.sharesOnboarder, p.governor) = _deployAndSetupAllProxies();
    }
}
