// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest, console2} from "test/Base.t.sol";
import {ProposalTestUtils} from "test/helpers/ProposalTestUtils.sol";
import {IGovernorBase} from "src/governor/interfaces/IGovernorBase.sol";
import {ExecutorBase} from "src/executor/base/ExecutorBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract FoundGovernorTest is BaseTest, ProposalTestUtils {
    uint256 internal constant MAX_BPS = 10_000;

    function setUp() public virtual override {
        super.setUp();
    }

    function _proposeFoundGovernor(
        address proposer,
        uint256 expectedProposalId
    )
        internal
        returns (uint256 proposalId)
    {
        proposalId = _propose(
            proposer,
            address(governor),
            0,
            abi.encodeCall(governor.foundGovernor, expectedProposalId),
            "foundGovernor(uint256)",
            "Let's get this party started."
        );
    }

    function _queueFoundGovernor(uint256 proposalId) internal returns (uint256) {
        return _queue(proposalId, address(governor), 0, abi.encodeCall(governor.foundGovernor, proposalId));
    }

    function _executeFoundGovernor(uint256 proposalId) internal returns (uint256) {
        return _execute(proposalId, address(governor), 0, abi.encodeCall(governor.foundGovernor, proposalId));
    }

    function test_GovernanceCanBeginAt() public {
        assertEq(governor.governanceCanBeginAt(), GOVERNOR.governanceCanBeginAt);
    }

    function test_RevertBefore_GovernanceCanBeginAt() public {
        uint256 expectedProposalId = _expectedProposalId();

        vm.warp(block.timestamp - 1);
        vm.expectRevert(
            abi.encodeWithSelector(IGovernorBase.GovernorCannotBeFoundedYet.selector, GOVERNOR.governanceCanBeginAt)
        );
        _proposeFoundGovernor(users.gwart, expectedProposalId);
    }

    function test_GovernanceFoundingVoteThreshold() public {
        uint256 expectedThreshold = Math.mulDiv(TOKEN.maxSupply, GOVERNOR.governanceThresholdBps, 10_000);
        uint256 threshold = governor.governanceFoundingVoteThreshold();
        assertEq(threshold, expectedThreshold);
    }

    function test_RevertWhen_GovernanceFoundingVoteThresholdNotMet() public {
        uint256 expectedProposalId = _expectedProposalId();

        // Miss the threshold by one
        uint256 threshold = governor.governanceFoundingVoteThreshold();
        uint256 amount = threshold - 1;

        // Mint for voting (delegates gwart shares to gwart)
        _mintSharesForVoting(users.gwart, amount);

        // Roll forward one block (proposals use clock() - 1 for vote supplies)
        vm.roll(block.number + 1);

        bytes memory thresholdNotMetError =
            abi.encodeWithSelector(IGovernorBase.GovernorFoundingVoteThresholdNotMet.selector, threshold, amount);

        vm.expectRevert(thresholdNotMetError);
        _proposeFoundGovernor(users.gwart, expectedProposalId);

        // Mint the missing shares to gwart
        _mintShares(users.gwart, threshold - amount);
        vm.roll(block.number + 1); // Roll forward to make sure shares count

        // Now proposal should be allowed
        uint256 proposalId = _proposeFoundGovernor(users.gwart, expectedProposalId);
        assertEq(proposalId, expectedProposalId);

        // Vote to succeed
        vm.roll(governor.proposalSnapshot(proposalId) + 1);
        vm.prank(users.gwart);
        governor.castVote(proposalId, 1);

        // Gwart burns a share, dipping below the proposal threshold again
        vm.prank(users.gwart);
        token.withdraw(threshold - amount, new IERC20[](0));

        // Queue for execution
        vm.roll(governor.proposalDeadline(proposalId) + 1);
        _queueFoundGovernor(proposalId);

        // Execution should fail due to the proposal threshold not begin met at the proposal deadline
        vm.warp(governor.proposalEta(proposalId));
        vm.expectRevert(abi.encodeWithSelector(ExecutorBase.CallReverted.selector, thresholdNotMetError));
        _executeFoundGovernor(proposalId);

        assertEq(false, governor.isFounded());
    }

    function test_RevertWhen_FoundGovernorActionIsInvalid() public {}
}
