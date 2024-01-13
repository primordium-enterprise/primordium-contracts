// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {TimelockAvatarTestUtils} from "test/helpers/TimelockAvatarTestUtils.sol";
import {ExecutorV1Harness} from "test/harness/ExecutorV1Harness.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AuthorizedInitializer} from "src/utils/AuthorizedInitializer.sol";
import {ITreasury} from "src/executor/interfaces/ITreasury.sol";

contract AuthorizedInitializerTest is TimelockAvatarTestUtils {
    function setUp() public virtual override {
        super.setUp();
        // Deploy the executor proxy with "gwart" user as the authorized initializer
        executor = ExecutorV1Harness(
            payable(
                address(
                    new ERC1967Proxy(
                        executorImpl, abi.encodeCall(AuthorizedInitializer.setAuthorizedInitializer, (users.gwart))
                    )
                )
            )
        );
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
