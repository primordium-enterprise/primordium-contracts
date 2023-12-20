// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {PRBTest} from "@prb/test/PRBTest.sol";
import {Enum} from "src/common/Enum.sol";
import {ExecutorBase} from "src/executor/base/ExecutorBase.sol";

contract ExecutorBaseTester is ExecutorBase {
    function execute(address target, uint256 value, bytes calldata data, Enum.Operation operation) public {
        _execute(target, value, data, operation);
    }
}

contract ExecutorBaseTest is PRBTest {
    ExecutorBaseTester tester = new ExecutorBaseTester();

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
        tester.execute(address(this), 0, abi.encodeCall(this.add, (10)), Enum.Operation.Call);
        assertEq(a, 10);
    }

    function test_ExecutePayment() public {
        vm.deal(address(tester), 1 ether);
        uint256 currentBalance = address(this).balance;
        tester.execute(address(this), 1 ether, hex"", Enum.Operation.Call);
        assertEq(address(this).balance, currentBalance + 1 ether);
    }

    function test_ExecuteRevert() public {
        bytes memory err = hex"0d5e7082"; // TestError.selector
        vm.expectRevert(abi.encodeWithSelector(ExecutorBase.CallReverted.selector, err));
        tester.execute(address(this), 0, abi.encodeCall(this.thisFunctionReverts, ()), Enum.Operation.Call);
    }

    receive() external payable {}
    fallback() external payable {}
}
