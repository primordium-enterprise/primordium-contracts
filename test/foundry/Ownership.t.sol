// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./GovernanceSetup.t.sol";

contract Ownership is Test, GovernanceSetup {

    function test_GovernorOwnsExecutor() external {
        assertEq(address(governor), executor.owner());
    }

    function test_ExecutorOwnsGovernor() external {
        assertEq(address(executor), governor.executor());
    }

    function test_ExecutorOwnsVotes() external {
        assertEq(address(executor), votes.executor());
    }

    function test_VotesIsExecutorToken() external {
        assertEq(address(votes), executor.votes());
    }

    function testFail_UpdateExecutorOnGovernor() external {
        governor.updateExecutor(Executor(payable(address(0x1))));
    }

}