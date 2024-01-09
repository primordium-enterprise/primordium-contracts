// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {ProposalTestUtils} from "test/helpers/ProposalTestUtils.sol";
import {IProposals} from "src/governor/interfaces/IProposals.sol";
import {IProposalVoting} from "src/governor/interfaces/IProposalVoting.sol";

contract ProposalVotingTest is BaseTest, ProposalTestUtils {
    function setUp() public virtual override {
        super.setUp();
        governor.harnessFoundGovernor();
    }

    function test_Fuzz_CastVote(uint16[3] memory shareAmounts, uint8[3] memory voteTypes) public {
        address payable[3] memory accounts = [users.gwart, users.bob, users.alice];
        for (uint256 i = 0; i < accounts.length; i++) {
            _mintSharesForVoting(accounts[i], shareAmounts[i]);
        }

        uint256 proposalId = _mockPropose(users.proposer);
        vm.roll(governor.proposalSnapshot(proposalId) + 1);

        // [0] - againstVotes, [1] - forVotes, [2] - abstainVotes
        uint256[3] memory expectedVotes;
        for (uint256 i = 0; i < accounts.length; i++) {
            uint8 voteType = voteTypes[i] % 4;
            if (voteType > uint8(type(IProposalVoting.VoteType).max)) {
                vm.expectRevert(IProposalVoting.GovernorInvalidVoteValue.selector);
            } else {
                expectedVotes[voteType] += shareAmounts[i];
            }
            vm.prank(accounts[i]);
            governor.castVote(proposalId, voteType);
        }

        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        assertEq(againstVotes, expectedVotes[0]);
        assertEq(forVotes, expectedVotes[1]);
        assertEq(abstainVotes, expectedVotes[2]);
    }
}