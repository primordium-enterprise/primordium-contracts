// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {TimelockAvatarTestUtils} from "test/helpers/TimelockAvatarTestUtils.sol";
import {ExecutorV1Harness} from "test/harness/ExecutorV1Harness.sol";
import {DistributorV1Harness} from "test/harness/DistributorV1Harness.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AuthorizedInitializer} from "src/utils/AuthorizedInitializer.sol";
import {ITreasury} from "src/executor/interfaces/ITreasury.sol";

contract AuthorizedInitializerTest is TimelockAvatarTestUtils {
    function setUp() public virtual override {
        super.setUp();
        // Reset initialization, and set gwart as the authorized initializer
        _uninitializeExecutor();
        executor.setAuthorizedInitializer(users.gwart);
    }

    function test_AuthorizeInitializer() public {
        vm.prank(users.gwart);
        _initializeExecutor(defaultModules);
    }

    function test_Revert_InvalidInitializer() public {
        vm.expectRevert(
            abi.encodeWithSelector(AuthorizedInitializer.UnauthorizedInitializer.selector, address(this), users.gwart)
        );
        _initializeExecutor(defaultModules);
    }

    function test_Revert_AlreadyInitialized() public {
        vm.prank(users.gwart);
        _initializeExecutor(defaultModules);
        vm.expectRevert(abi.encodeWithSelector(AuthorizedInitializer.AlreadyInitialized.selector));
        executor.setAuthorizedInitializer(address(this));
    }

    function test_Revert_AuthorizedInitializerAlreadySet() public {
        vm.expectRevert(abi.encodeWithSelector(AuthorizedInitializer.AuthorizedInitializerAlreadySet.selector));
        executor.setAuthorizedInitializer(address(this));
    }
}
