// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {Enum} from "src/common/Enum.sol";

contract TimelockAvatarTestUtils is BaseTest {
    address internal constant MODULES_HEAD = address(0x01);
    uint256 internal constant GRACE_PERIOD = 14 days;

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
        _initializeDistributor();
        _initializeExecutor(defaultModules);
    }

    function _reverseModulesArray(address[] memory modules) internal pure returns (address[] memory reversedModules) {
        reversedModules = new address[](modules.length);
        for (uint256 i = 0; i < modules.length; i++) {
            reversedModules[i] = modules[modules.length - (i + 1)];
        }
    }

    function _randModuleSelection(uint256 seed, bool allowInvalidModule) internal view returns (address module) {
        uint256 mod = defaultModules.length;
        if (allowInvalidModule) {
            mod += 1;
        }
        uint256 index = seed % mod;
        if (index < defaultModules.length) {
            module = defaultModules[index];
        } else {
            module = users.maliciousUser;
        }
    }

    function _randEnumOperation(uint8 operationSeed) internal pure returns (Enum.Operation operation) {
        operation = Enum.Operation(operationSeed % (uint8(type(Enum.Operation).max) + 1));
    }
}