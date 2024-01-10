// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";

contract TimelockAvatarTestUtils is BaseTest {
    address[] internal defaultModules;

    constructor() {
        // Modules default to this test contract, and gwart
        defaultModules = new address[](2);
        defaultModules[0] = address(this);
        defaultModules[1] = users.gwart;
    }

    function setUp() public virtual override {
        _deploy();
        _initializeToken();
        _initializeOnboarder();
        _initializeExecutor(defaultModules);
    }
}