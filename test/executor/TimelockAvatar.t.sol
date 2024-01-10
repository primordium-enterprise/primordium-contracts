// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest, console2} from "test/Base.t.sol";
import {TimelockAvatarTestUtils} from "test/helpers/TimelockAvatarTestUtils.sol";
import {IAvatar} from "src/executor/interfaces/IAvatar.sol";
import {ITimelockAvatar} from "src/executor/interfaces/ITimelockAvatar.sol";
import {Enum} from "src/common/Enum.sol";
import {SelfAuthorized} from "src/executor/base/SelfAuthorized.sol";

contract TimelockAvatarTest is BaseTest, TimelockAvatarTestUtils {
    function setUp() public virtual override(BaseTest, TimelockAvatarTestUtils) {
        super.setUp();
    }

    function test_Fuzz_HashOperation(address to, uint256 value, bytes memory data, uint8 operation) public {
        // Operation must not be greater than type(Enum.Operation).max, or error will occur
        operation = operation % (uint8(type(Enum.Operation).max) + 1);
        assertEq(
            executor.hashOperation(to, value, data, Enum.Operation(operation)),
            keccak256(abi.encode(to, value, data, operation))
        );
    }

    function test_GetModulesPaginated() public {
        for (uint256 i = 0; i < defaultModules.length; i++) {
            assertEq(true, executor.isModuleEnabled(defaultModules[i]));
        }
        (address[] memory enabledModules,) = executor.getModulesPaginated(address(0x01), 100);
        assertEq(_reverseModulesArray(defaultModules), enabledModules);
    }

    function test_Fuzz_EnableModule(address newModule) public {
        vm.prank(users.maliciousUser);
        vm.expectRevert(SelfAuthorized.OnlySelfAuthorized.selector);
        executor.enableModule(newModule);

        bool expectEnabled = false;
        if (newModule == address(0) || newModule == address(0x01)) {
            vm.expectRevert(abi.encodeWithSelector(ITimelockAvatar.InvalidModuleAddress.selector, newModule));
        } else if (executor.isModuleEnabled(newModule)) {
            vm.expectRevert(abi.encodeWithSelector(ITimelockAvatar.ModuleAlreadyEnabled.selector, newModule));
        } else {
            expectEnabled = true;
            vm.expectEmit(true, false, false, false, address(executor));
            emit IAvatar.EnabledModule(newModule);
        }

        vm.prank(address(executor));
        executor.enableModule(newModule);

        assertEq(expectEnabled, executor.isModuleEnabled(newModule));
        if (expectEnabled) {
            address[] memory expectedEnabledModules = new address[](defaultModules.length + 1);
            for (uint256 i = 0; i < defaultModules.length; i++) {
                expectedEnabledModules[i] = defaultModules[i];
            }
            expectedEnabledModules[expectedEnabledModules.length - 1] = newModule;

            (address[] memory enabledModules,) = executor.getModulesPaginated(address(0x01), 100);
            assertEq(_reverseModulesArray(expectedEnabledModules), enabledModules);
        }
    }
}
