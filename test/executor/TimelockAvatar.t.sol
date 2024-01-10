// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest, console2} from "test/Base.t.sol";
import {TimelockAvatarTestUtils} from "test/helpers/TimelockAvatarTestUtils.sol";
import {IAvatar} from "src/executor/interfaces/IAvatar.sol";
import {ITimelockAvatar} from "src/executor/interfaces/ITimelockAvatar.sol";
import {Enum} from "src/common/Enum.sol";
import {SelfAuthorized} from "src/executor/base/SelfAuthorized.sol";
import {ExecutorBase} from "src/executor/base/ExecutorBase.sol";

contract TimelockAvatarTest is TimelockAvatarTestUtils {
    error InvalidExecutingModule(address executingModule);

    function setUp() public virtual override {
        super.setUp();
    }

    function verifyExecutingModule(address expectedModule) public view {
        address executingModule = executor.executingModule();
        if (expectedModule != executingModule) {
            revert InvalidExecutingModule(executingModule);
        }
    }

    function test_Fuzz_HashOperation(address to, uint256 value, bytes memory data, uint8 operationSeed) public {
        // Operation must not be greater than type(Enum.Operation).max, or error will occur
        Enum.Operation operation = _randEnumOperation(operationSeed);
        assertEq(executor.hashOperation(to, value, data, operation), keccak256(abi.encode(to, value, data, operation)));
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

    function test_Fuzz_DisableModule(uint256 moduleIndex) public {
        address moduleToRemove = _randModuleSelection(moduleIndex, false);
        address prevModule;
        {
            (address[] memory currentModules,) = executor.getModulesPaginated(MODULES_HEAD, 100);
            for (uint256 i = 0; i < currentModules.length; i++) {
                if (currentModules[i] == moduleToRemove) {
                    if (i == 0) {
                        prevModule = MODULES_HEAD;
                    } else {
                        prevModule = currentModules[i - 1];
                    }
                    break;
                }
            }
        }

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

    function test_Fuzz_SetMinDelay(uint24 newMinDelay) public {
        // Revert if not self
        vm.prank(users.maliciousUser);
        vm.expectRevert(SelfAuthorized.OnlySelfAuthorized.selector);
        executor.setMinDelay(newMinDelay);

        uint256 expectedMinDelay = EXECUTOR.minDelay;

        uint256 min = executor.MIN_DELAY();
        uint256 max = executor.MAX_DELAY();
        if (newMinDelay < min || newMinDelay > max) {
            vm.expectRevert(abi.encodeWithSelector(ITimelockAvatar.MinDelayOutOfRange.selector, min, max));
        } else {
            expectedMinDelay = newMinDelay;
            vm.expectEmit(false, false, false, false, address(executor));
            emit ITimelockAvatar.MinDelayUpdate(EXECUTOR.minDelay, newMinDelay);
        }

        vm.prank(address(executor));
        executor.setMinDelay(newMinDelay);

        assertEq(expectedMinDelay, executor.getMinDelay());

        // Revert with insufficient delay
        vm.prank(defaultModules[0]);
        vm.expectRevert(abi.encodeWithSelector(ITimelockAvatar.DelayOutOfRange.selector, expectedMinDelay, max));
        executor.scheduleTransactionFromModuleReturnData(users.gwart, 0, "", Enum.Operation.Call, expectedMinDelay - 1);

        // Operation delay should default to minDelay
        vm.prank(defaultModules[0]);
        (, bytes memory returnData) =
            executor.execTransactionFromModuleReturnData(users.gwart, 0, "", Enum.Operation.Call);
        (uint256 opNonce) = abi.decode(returnData, (uint256));
        assertEq(block.timestamp + expectedMinDelay, executor.getOperationExecutableAt(opNonce));
    }

    struct ExecTransactionFromModuleExpectations {
        bool success;
        uint256 nextOpNonce;
        uint256 executableAt;
        bytes32 opHash;
        address module;
        uint256 createdAt;
        ITimelockAvatar.OperationStatus opStatus;
    }

    function _setupExecTransactionFromModule(
        address module,
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256 delay
    )
        internal
        returns (uint256 opNonce, ExecTransactionFromModuleExpectations memory expectations)
    {
        opNonce = executor.getNextOperationNonce();
        uint256 minDelay = executor.getMinDelay();
        uint256 maxDelay = executor.MAX_DELAY();

        // Zero value for delay will default to the minDelay
        uint256 expectedDelay = delay == 0 ? minDelay : delay;

        expectations.nextOpNonce = opNonce;
        if (!executor.isModuleEnabled(module)) {
            vm.expectRevert(abi.encodeWithSelector(ITimelockAvatar.ModuleNotEnabled.selector, module));
        } else if (expectedDelay < minDelay || expectedDelay > maxDelay) {
            vm.expectRevert(abi.encodeWithSelector(ITimelockAvatar.DelayOutOfRange.selector, minDelay, maxDelay));
        } else {
            expectations.success = true;
            expectations.nextOpNonce = opNonce + 1;
            expectations.executableAt = block.timestamp + expectedDelay;
            expectations.opHash = keccak256(abi.encode(to, value, data, operation));
            expectations.module = module;
            expectations.createdAt = block.timestamp;
            expectations.opStatus = ITimelockAvatar.OperationStatus.Pending;

            vm.expectEmit(true, true, false, true, address(executor));
            emit ITimelockAvatar.OperationScheduled(opNonce, module, to, value, data, operation, expectedDelay);
        }
    }

    function _execTransactionFromModuleAsserts(
        uint256 opNonce,
        bool success,
        bytes memory returnData,
        ExecTransactionFromModuleExpectations memory expectations
    )
        internal
    {
        assertEq(expectations.success, success);
        assertEq(expectations.nextOpNonce, executor.getNextOperationNonce());
        assertEq(expectations.executableAt, executor.getOperationExecutableAt(opNonce));
        assertEq(expectations.opHash, executor.getOperationHash(opNonce));
        assertEq(expectations.module, executor.getOperationModule(opNonce));
        assertEq(uint8(expectations.opStatus), uint8(executor.getOperationStatus(opNonce)));

        if (returnData.length > 0) {
            (uint256 rOpNonce, bytes32 rOpHash, uint256 rExecutableAt) =
                abi.decode(returnData, (uint256, bytes32, uint256));
            assertEq(opNonce, rOpNonce);
            assertEq(expectations.opHash, rOpHash);
            assertEq(expectations.executableAt, rExecutableAt);
        }

        (address _module, uint256 _executableAt, uint256 _createdAt, bytes32 _opHash) =
            executor.getOperationDetails(opNonce);
        assertEq(expectations.module, _module);
        assertEq(expectations.executableAt, _executableAt);
        assertEq(expectations.createdAt, _createdAt);
        assertEq(expectations.opHash, _opHash);
    }

    function test_Fuzz_ExecTransactionFromModule(
        uint256 moduleIndex,
        address to,
        uint256 value,
        bytes memory data,
        uint8 operationSeed
    )
        public
    {
        address module = _randModuleSelection(moduleIndex, true);
        Enum.Operation operation = _randEnumOperation(operationSeed);

        (uint256 opNonce, ExecTransactionFromModuleExpectations memory expectations) =
            _setupExecTransactionFromModule(module, to, value, data, operation, executor.getMinDelay());

        vm.prank(module);
        bool success = executor.execTransactionFromModule(to, value, data, operation);

        _execTransactionFromModuleAsserts(opNonce, success, "", expectations);
    }

    function test_Fuzz_ExecTransactionFromModuleReturnData(
        uint256 moduleIndex,
        address to,
        uint256 value,
        bytes memory data,
        uint8 operationSeed
    )
        public
    {
        address module = _randModuleSelection(moduleIndex, true);
        Enum.Operation operation = _randEnumOperation(operationSeed);

        (uint256 opNonce, ExecTransactionFromModuleExpectations memory expectations) =
            _setupExecTransactionFromModule(module, to, value, data, operation, executor.getMinDelay());

        vm.prank(module);
        (bool success, bytes memory returnData) =
            executor.execTransactionFromModuleReturnData(to, value, data, operation);

        _execTransactionFromModuleAsserts(opNonce, success, returnData, expectations);
    }

    function test_Fuzz_ScheduleTransactionFromModuleReturnData(
        uint256 moduleIndex,
        address to,
        uint256 value,
        bytes memory data,
        uint8 operationSeed,
        uint24 delay
    )
        public
    {
        address module = _randModuleSelection(moduleIndex, true);
        Enum.Operation operation = _randEnumOperation(operationSeed);

        (uint256 opNonce, ExecTransactionFromModuleExpectations memory expectations) =
            _setupExecTransactionFromModule(module, to, value, data, operation, delay);

        vm.prank(module);
        (bool success, bytes memory returnData) =
            executor.scheduleTransactionFromModuleReturnData(to, value, data, operation, delay);

        _execTransactionFromModuleAsserts(opNonce, success, returnData, expectations);
    }

    function test_ExecuteOperation() public {
        address to = address(this);
        uint256 value = 0;
        bytes memory data = abi.encodeCall(this.verifyExecutingModule, (address(this)));
        Enum.Operation operation = Enum.Operation.Call;

        (bool success, bytes memory returnData) =
            executor.execTransactionFromModuleReturnData(to, value, data, operation);
        assertEq(true, success);

        (uint256 opNonce,, uint256 eta) = abi.decode(returnData, (uint256, bytes32, uint256));

        // Revert if pre-eta
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockAvatar.InvalidOperationStatus.selector,
                ITimelockAvatar.OperationStatus.Pending,
                ITimelockAvatar.OperationStatus.Ready
            )
        );
        executor.executeOperation(opNonce, to, value, data, operation);

        // Revert if expired
        vm.warp(eta + GRACE_PERIOD);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockAvatar.InvalidOperationStatus.selector,
                ITimelockAvatar.OperationStatus.Expired,
                ITimelockAvatar.OperationStatus.Ready
            )
        );
        executor.executeOperation(opNonce, to, value, data, operation);

        // Revert if call not coming from operation module
        vm.warp(eta);
        vm.prank(users.alice);
        vm.expectRevert(abi.encodeWithSelector(ITimelockAvatar.UnauthorizedModule.selector));
        executor.executeOperation(opNonce, to, value, data, operation);

        // Success (checking executing module during execution)
        assertEq(executor.executingModule(), MODULES_HEAD);
        vm.expectEmit(true, false, false, true, address(executor));
        emit ExecutorBase.CallExecuted(to, value, data, operation);
        vm.expectEmit(true, true, false, false, address(executor));
        emit ITimelockAvatar.OperationExecuted(opNonce, address(this));
        executor.executeOperation(opNonce, to, value, data, operation);
        assertEq(executor.executingModule(), MODULES_HEAD);

        assertEq(uint8(ITimelockAvatar.OperationStatus.Done), uint8(executor.getOperationStatus(opNonce)));
    }

    function test_CancelOperation() public {
        address to = address(this);
        uint256 value = 0;
        bytes memory data = abi.encodeCall(this.verifyExecutingModule, (address(this)));
        Enum.Operation operation = Enum.Operation.Call;

        (bool success, bytes memory returnData) =
            executor.execTransactionFromModuleReturnData(to, value, data, operation);
        assertEq(true, success);

        (uint256 opNonce,, uint256 eta) = abi.decode(returnData, (uint256, bytes32, uint256));

        // Cannot cancel if past pending period
        vm.warp(eta);
        vm.expectRevert(
            abi.encodeWithSelector(
                ITimelockAvatar.InvalidOperationStatus.selector,
                ITimelockAvatar.OperationStatus.Ready,
                ITimelockAvatar.OperationStatus.Pending
            )
        );
        executor.cancelOperation(opNonce);

        // Only operation module can cancel
        vm.warp(eta - 1);
        vm.prank(users.alice);
        vm.expectRevert(abi.encodeWithSelector(ITimelockAvatar.UnauthorizedModule.selector));
        executor.cancelOperation(opNonce);

        // Success
        vm.expectEmit(true, true, false, false, address(executor));
        emit ITimelockAvatar.OperationCanceled(opNonce, address(this));
        executor.cancelOperation(opNonce);

        assertEq(uint8(ITimelockAvatar.OperationStatus.Canceled), uint8(executor.getOperationStatus(opNonce)));
    }
}
