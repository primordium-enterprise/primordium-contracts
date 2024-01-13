// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.20;

import {BaseScriptV1, console2} from "./BaseV1.s.sol";
import {DeployImplementationsV1} from "./DeployImplementationsV1.s.sol";
import {DeployAndSetUpProxiesV1} from "./DeployAndSetUpProxiesV1.s.sol";

contract DeployV1 is DeployImplementationsV1, DeployAndSetUpProxiesV1 {
    function run() public virtual override(DeployImplementationsV1, DeployAndSetUpProxiesV1) {
        DeployImplementationsV1.run();
        DeployAndSetUpProxiesV1.run();
    }
}