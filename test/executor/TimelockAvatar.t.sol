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
        (address[] memory enabledModules,) = executor.getModulesPaginated(MODULES_HEAD, 100);
        assertEq(_reverseModulesArray(defaultModules), enabledModules);
    }

    function test_Fuzz_EnableModule(address newModule) public {
        vm.prank(users.maliciousUser);
        vm.expectRevert(SelfAuthorized.OnlySelfAuthorized.selector);
        executor.enableModule(newModule);

        bool expectEnabled = false;
        if (newModule == address(0) || newModule == MODULES_HEAD) {
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

            (address[] memory enabledModules,) = executor.getModulesPaginated(MODULES_HEAD, 100);
            assertEq(_reverseModulesArray(expectedEnabledModules), enabledModules);
        }
    }

    function test_Fuzz_DisableModule(uint256 index) public {
        index = index % (defaultModules.length);
        address moduleToRemove = defaultModules[index];

        // Prev module is actually the next module, as the modules are listed in reverse
        address prevModule = index < defaultModules.length - 1 ? defaultModules[index + 1] : MODULES_HEAD;

        // Revert if not self
        vm.prank(users.maliciousUser);
        vm.expectRevert(SelfAuthorized.OnlySelfAuthorized.selector);
        executor.disableModule(prevModule, moduleToRemove);

        // Revert if module/prevModule is not valid
        vm.prank(address(executor));
        vm.expectRevert(abi.encodeWithSelector(ITimelockAvatar.InvalidPreviousModuleAddress.selector, prevModule));
        executor.disableModule(prevModule, address(0x20));

        vm.prank(address(executor));
        vm.expectRevert(abi.encodeWithSelector(ITimelockAvatar.InvalidPreviousModuleAddress.selector, address(0x20)));
        executor.disableModule(address(0x20), moduleToRemove);

        // Success as executor
        vm.prank(address(executor));
        vm.expectEmit(true, false, false, false, address(executor));
        emit IAvatar.DisabledModule(moduleToRemove);
        executor.disableModule(prevModule, moduleToRemove);

        // Verify paginated list
        address[] memory expectedEnabledModules = new address[](defaultModules.length - 1);
        bool skipped = false;
        for (uint256 i = 0; i < defaultModules.length; i++) {
            if (defaultModules[i] == moduleToRemove) {
                skipped = true;
                continue;
            }

            expectedEnabledModules[skipped ? i - 1 : i] = defaultModules[i];
        }

        (address[] memory enabledModules,) = executor.getModulesPaginated(MODULES_HEAD, 100);
        assertEq(_reverseModulesArray(expectedEnabledModules), enabledModules);
    }
}
