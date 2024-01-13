// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import {BaseScriptV1, console2} from "./BaseV1.s.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PrimordiumTokenV1} from "src/token/PrimordiumTokenV1.sol";
import {PrimordiumSharesOnboarderV1} from "src/onboarder/PrimordiumSharesOnboarderV1.sol";
import {PrimordiumGovernorV1} from "src/governor/PrimordiumGovernorV1.sol";
import {PrimordiumExecutorV1} from "src/executor/PrimordiumExecutorV1.sol";
import {DistributorV1} from "src/executor/extensions/DistributorV1.sol";

contract DeployProxiesV1 is BaseScriptV1 {
    function run() public virtual {

        // address executor;

        // SharesTokenSettings memory sharesTokenSettings = SharesTokenSettings({
        //     owner: computedExecutorAddress,
        //     name: "Primordium",
        //     symbol: "MUSHI",
        //     sharesTokenInit: SharesTokenInit({
        //         maxSupply: 100,

        //     })
        // });

    }

}