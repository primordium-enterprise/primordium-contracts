// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";

contract DeploymentsTest is BaseTest {
    function setUp() public virtual override {}

    function test_DefaultDeployment() public {
        _deployAndInitializeDefaults();
    }
}