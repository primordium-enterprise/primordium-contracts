// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import {BaseScriptV1, console2} from "./BaseV1.s.sol";
import {PrimordiumDAOConfigV1} from "./config/PrimordiumDAOConfigV1.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PrimordiumTokenV1} from "src/token/PrimordiumTokenV1.sol";
import {PrimordiumSharesOnboarderV1} from "src/onboarder/PrimordiumSharesOnboarderV1.sol";
import {PrimordiumGovernorV1} from "src/governor/PrimordiumGovernorV1.sol";
import {PrimordiumExecutorV1} from "src/executor/PrimordiumExecutorV1.sol";
import {DistributorV1} from "src/executor/extensions/DistributorV1.sol";

contract DeployAndSetUpProxiesV1 is BaseScriptV1, PrimordiumDAOConfigV1 {
    function run() public virtual broadcast {

        address executor = _deploy_ExecutorV1();
        console2.log("Executor:", executor);

        address token = _deploy_TokenV1();
        console2.log("Token:", token);

        address sharesOnboarder = _deploy_SharesOnboarderV1();
        console2.log("Shares Onboarder:", sharesOnboarder);

        address governor = _deploy_GovernorV1();
        console2.log("Governor:", governor);

        // Still need to setup the executor
        PrimordiumExecutorV1(payable(executor)).setUp(_getExecutorV1InitParams());
    }

}