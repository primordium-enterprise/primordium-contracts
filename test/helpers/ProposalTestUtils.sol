// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {ExecutorBase} from "src/executor/base/ExecutorBase.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

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

    function _passAndQueueProposal(
        uint256 proposalId,
        address voter,
        address target,
        uint256 value,
        bytes memory data
    ) internal returns (uint256) {
        uint256 currentClock = token.clock();
        uint256 voterShares = token.getPastVotes(voter, currentClock - 1);
        uint256 requiredShares = governor.quorumBps(currentClock) * token.maxSupply() / MAX_BPS;
        if (voterShares < requiredShares) {
            _mintSharesForVoting(voter, requiredShares - voterShares);
            vm.roll(currentClock + 1);
        }

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
    function _proposePassAndQueueOnlyGovernanceUpdate(
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
        _passAndQueueProposal(proposalId, users.proposer, target, 0, data);
    }

    /// @dev Helper to execute only governance update
    function _executeOnlyGovernanceUpdate(
        uint256 proposalId,
        bytes memory data,
        bytes memory expectedExecutionError
    ) internal returns (uint256) {
        return _executePassedProposal(proposalId, address(governor), 0, data, expectedExecutionError);
    }

    function _updateGovernorSetting(address voter, string memory signature, uint256 value) internal {
        bytes memory data = abi.encodePacked(bytes4(keccak256(abi.encodePacked(signature))), value);
        _runOnlyGovernanceUpdate(voter, data, signature);
    }

    function _runOnlyGovernanceUpdate(address voter, bytes memory data, string memory signature) internal {
        uint256 proposalId = _propose(users.proposer, address(governor), 0, data, signature, "run governance update");
        _passAndQueueProposal(proposalId, voter, address(governor), 0, data);
        _executePassedProposal(proposalId, address(governor), 0, data, "");
    }

    /// @dev Quick mock proposal, provided the proposer address
    function _mockPropose(address proposer) internal returns (uint256 proposalId) {
        string memory signature = "testSignature()";
        return _propose(
            proposer,
            address(0x01),
            0,
            abi.encodePacked(bytes4(keccak256(abi.encodePacked(signature)))),
            signature,
            "mock"
        );
    }
}
