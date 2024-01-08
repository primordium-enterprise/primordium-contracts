// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {ExecutorBase} from "src/executor/base/ExecutorBase.sol";

contract ProposalTestUtils is BaseTest {
    /// @dev Makes external call to governor for proposal count, so call this before any call expectations are set
    function _expectedProposalId() internal view returns (uint256 expectedProposalId) {
        expectedProposalId = governor.proposalCount() + 1;
    }

    function _propose(
        address proposer,
        address target,
        uint256 value,
        bytes memory data,
        string memory signature,
        string memory description
    )
        internal
        returns (uint256 proposalId)
    {
        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        values[0] = value;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = data;
        string[] memory signatures = new string[](1);
        signatures[0] = signature;

        vm.prank(proposer);
        proposalId = governor.propose(targets, values, calldatas, signatures, description);
    }

    function _queue(uint256 proposalId, address target, uint256 value, bytes memory data) internal returns (uint256) {
        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        values[0] = value;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = data;

        return governor.queue(proposalId, targets, values, calldatas);
    }

    function _execute(
        uint256 proposalId,
        address target,
        uint256 value,
        bytes memory data
    )
        internal
        returns (uint256)
    {
        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        values[0] = value;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = data;

        return governor.execute(proposalId, targets, values, calldatas);
    }

    function _queueAndPassProposal(
        uint256 proposalId,
        address voter,
        address target,
        uint256 value,
        bytes memory data
    ) internal returns (uint256) {
        vm.roll(governor.proposalSnapshot(proposalId) + 1);
        vm.prank(voter);
        governor.castVote(proposalId, 1);

        vm.roll(governor.proposalDeadline(proposalId) + 1);
        return _queue(proposalId, target, value, data);
    }

    function _executePassedProposal(
        uint256 proposalId,
        address target,
        uint256 value,
        bytes memory data,
        bytes memory expectedExecutionError
    ) internal returns (uint256) {
        vm.warp(governor.proposalEta(proposalId));
        if (expectedExecutionError.length > 0) {
            vm.expectRevert(abi.encodeWithSelector(ExecutorBase.CallReverted.selector, expectedExecutionError));
        }
        return _execute(proposalId, target, value, data);
    }

    /// @dev Helper to propose an only governance update (mints required votes to the "proposer" user)
    function _proposeQueueAndPassOnlyGovernanceUpdate(
        bytes memory data,
        string memory signature
    )
        internal
        returns (uint256 proposalId)
    {
        uint256 requiredVoteShares = GOVERNOR.quorumBps * TOKEN.maxSupply / MAX_BPS;
        _mintSharesForVoting(users.proposer, requiredVoteShares);
        vm.roll(block.number + 1);

        address target = address(governor);

        proposalId = _propose(users.proposer, target, 0, data, signature, "updating a setting");
        _queueAndPassProposal(proposalId, users.proposer, target, 0, data);
    }

    /// @dev Helper to queue and pass only governance update
    function _queueAndPassOnlyGovernanceUpdate(
        uint256 proposalId,
        bytes memory data
    ) internal returns (uint256) {
        return _queueAndPassProposal(proposalId, users.proposer, address(governor), 0, data);
    }

    /// @dev Helper to execute only governance update
    function _executeOnlyGovernanceUpdate(
        uint256 proposalId,
        bytes memory data,
        bytes memory expectedExecutionError
    ) internal returns (uint256) {
        return _executePassedProposal(proposalId, address(governor), 0, data, expectedExecutionError);
    }
}