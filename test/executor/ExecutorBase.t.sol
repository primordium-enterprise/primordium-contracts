// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {PRBTest} from "@prb/test/PRBTest.sol";
import {VmSafe} from "@prb/test/Vm.sol";
import {Enum} from "src/common/Enum.sol";
import {ExecutorBase} from "src/executor/base/ExecutorBase.sol";
import {console2} from "forge-std/console2.sol";

bytes32 constant TEST_DELEGATECALL_STORAGE = keccak256("TestDelegateCall");
string constant TEST_REVERT_MESSAGE = "DelegateCallNotAllowed";

contract TestDelegateCall {
    error TestDelegateCallRevert(string reason);

    address _this;

    constructor() {
        _this = address(this);
    }

    function setTestDelegateCallStorage(uint256 value) public {
        bytes32 slot = TEST_DELEGATECALL_STORAGE;
        assembly ("memory-safe") {
            sstore(slot, value)
        }
    }

    function delegateCallReverts() public view {
        if (address(this) != _this) {
            revert TestDelegateCallRevert(TEST_REVERT_MESSAGE);
        }
    }
}

contract ExecutorBaseTester is ExecutorBase {
    function execute(address target, uint256 value, bytes calldata data, Enum.Operation operation) public {
        _execute(target, value, data, operation);
    }

    function getTestDelegateCallStorage() public view returns (uint256 value) {
        bytes32 slot = TEST_DELEGATECALL_STORAGE;
        assembly ("memory-safe") {
            value := sload(slot)
        }
    }
}

contract ExecutorBaseTest is PRBTest {
    ExecutorBaseTester executorBase = new ExecutorBaseTester();
    TestDelegateCall testDelegateCall = new TestDelegateCall();

    uint256 public a;

    bytes constant TEST_REVERT = "TEST_REVERT";

    error TestError();

    function add(uint256 addAmount) external {
        a += addAmount;
    }

    function thisFunctionReverts() external pure {
        revert TestError();
    }

    function test_ExecuteFunction() public {
        vm.recordLogs();
        bytes memory data = abi.encodeCall(this.add, (10));
        executorBase.execute(address(this), 0, data, Enum.Operation.Call);
        VmSafe.Log[] memory logs = vm.getRecordedLogs();

        // Expect a single "CallExecuted" event
        VmSafe.Log memory log = logs[0];

        // Check topics
        bytes32[] memory expectedTopics = new bytes32[](2);
        expectedTopics[0] = ExecutorBase.CallExecuted.selector;
        expectedTopics[1] = bytes32(uint256(uint160(address(this))));
        assertEq(log.topics, expectedTopics);

        // Check abi encoded event data
        assertEq(log.data, abi.encode(0, data, Enum.Operation.Call));

        // Check that update occurred properly
        assertEq(a, 10);
    }

    function test_ExecutePayment() public {
        vm.deal(address(executorBase), 1 ether);
        uint256 currentBalance = address(this).balance;
        executorBase.execute(address(this), 1 ether, hex"", Enum.Operation.Call);
        assertEq(address(this).balance, currentBalance + 1 ether);
    }

    function test_ExecuteRevert() public {
        // bytes memory err = hex"0d5e7082"; // TestError.selector
        vm.expectRevert(
            abi.encodeWithSelector(ExecutorBase.CallReverted.selector, (
                abi.encodeWithSelector(TestError.selector)
            )));
        executorBase.execute(address(this), 0, abi.encodeCall(this.thisFunctionReverts, ()), Enum.Operation.Call);
    }

    function test_DelegateExecute() public {
        uint256 testValue = 100;
        executorBase.execute(
            address(testDelegateCall),
            0,
            abi.encodeCall(testDelegateCall.setTestDelegateCallStorage, (testValue)),
            Enum.Operation.DelegateCall
        );
        assertEq(executorBase.getTestDelegateCallStorage(), testValue);
    }

    function test_DelegateExecuteRevert() public {
        vm.expectRevert(
            abi.encodeWithSelector(ExecutorBase.CallReverted.selector, (
                abi.encodeWithSelector(TestDelegateCall.TestDelegateCallRevert.selector, (TEST_REVERT_MESSAGE))
            ))
        );
        executorBase.execute(
            address(testDelegateCall),
            0,
            abi.encodeCall(testDelegateCall.delegateCallReverts, ()),
            Enum.Operation.DelegateCall
        );
    }

    receive() external payable {}
    fallback() external payable {}
}
