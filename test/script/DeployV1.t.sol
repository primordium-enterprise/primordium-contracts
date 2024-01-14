// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {PRBTest} from "@prb/test/PRBTest.sol";
import {console2} from "forge-std/console2.sol";
import {DeployV1} from "script/DeployV1.s.sol";

contract DeployV1Test is PRBTest {

    DeployV1 deployScript = new DeployV1();

    function setUp() public {
        deployScript.run();
    }

    function test_Deploy() public view {
        console2.logBytes(address(0x7C46a83fE28F0b283e354E1f783470157Ab242dc).code);
    }

}