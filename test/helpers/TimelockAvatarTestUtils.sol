// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";

contract TimelockAvatarTestUtils is BaseTest {
    address internal constant MODULES_HEAD = address(0x01);

    address[] internal defaultModules;

    constructor() {
        // Modules default to this test contract, gwart, and alice
        defaultModules = new address[](3);
        defaultModules[0] = address(this);
        defaultModules[1] = users.gwart;
        defaultModules[2] = users.alice;
    }

    function setUp() public virtual override {
        _deploy();
        _initializeToken();
        _initializeOnboarder();
        _initializeExecutor(defaultModules);
    }

    function _reverseModulesArray(address[] memory modules) internal pure returns (address[] memory reversedModules) {
        reversedModules = new address[](modules.length);
        for (uint256 i = 0; i < modules.length; i++) {
            reversedModules[i] = modules[modules.length - (i + 1)];
        }
    }
}