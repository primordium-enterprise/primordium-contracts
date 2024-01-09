// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BaseTest} from "test/Base.t.sol";
import {ProposalTestUtils} from "test/helpers/ProposalTestUtils.sol";
import {IProposals} from "src/governor/interfaces/IProposals.sol";
import {IProposalVoting} from "src/governor/interfaces/IProposalVoting.sol";

contract ProposalVotingTest is BaseTest, ProposalTestUtils {
    uint8 maxVoteType = uint8(type(IProposalVoting.VoteType).max);

    function setUp() public virtual override {
        super.setUp();
        governor.harnessFoundGovernor();
    }

    function _setupVotes(
        uint16[3] memory shareAmounts,
        uint8[3] memory voteTypes
    )
        internal
        returns (address payable[3] memory accounts, uint256 proposalId, uint256[3] memory expectedVotes)
    {
        accounts = [users.gwart, users.bob, users.alice];
        for (uint256 i = 0; i < accounts.length; i++) {
            _mintSharesForVoting(accounts[i], shareAmounts[i]);
            uint8 voteType = voteTypes[i] % (maxVoteType + 2);
            voteTypes[i] = voteType;
            if (voteType <= maxVoteType) {
                expectedVotes[voteType] += shareAmounts[i];
            }
        }

        proposalId = _mockPropose(users.proposer);
        vm.roll(governor.proposalSnapshot(proposalId) + 1);
    }

    function _checkVotes(uint256 proposalId, uint256[3] memory expectedVotes) internal {
        (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes) = governor.proposalVotes(proposalId);
        assertEq(againstVotes, expectedVotes[0], "Invalid againstVotes");
        assertEq(forVotes, expectedVotes[1], "Invalid forVotes");
        assertEq(abstainVotes, expectedVotes[2], "Invalid abstainVotes");
    }

    function test_Fuzz_CastVote(uint16[3] memory shareAmounts, uint8[3] memory voteTypes) public {
        (address payable[3] memory accounts, uint256 proposalId, uint256[3] memory expectedVotes) =
            _setupVotes(shareAmounts, voteTypes);

        for (uint256 i = 0; i < accounts.length; i++) {
            if (voteTypes[i] > maxVoteType) {
                vm.expectRevert(IProposalVoting.GovernorInvalidVoteValue.selector);
            } else {
                vm.expectEmit(true, true, false, true, address(governor));
                emit IProposalVoting.VoteCast(accounts[i], proposalId, voteTypes[i], shareAmounts[i], "");
            }
            vm.prank(accounts[i]);
            governor.castVote(proposalId, voteTypes[i]);
        }

        _checkVotes(proposalId, expectedVotes);
    }

    function test_Fuzz_CastVoteWithReason(
        uint16[3] memory shareAmounts,
        uint8[3] memory voteTypes,
        string[3] memory reasons
    )
        public
    {
        (address payable[3] memory accounts, uint256 proposalId, uint256[3] memory expectedVotes) =
            _setupVotes(shareAmounts, voteTypes);

        for (uint256 i = 0; i < accounts.length; i++) {
            if (voteTypes[i] > maxVoteType) {
                vm.expectRevert(IProposalVoting.GovernorInvalidVoteValue.selector);
            } else {
                vm.expectEmit(true, true, false, true, address(governor));
                emit IProposalVoting.VoteCast(accounts[i], proposalId, voteTypes[i], shareAmounts[i], reasons[i]);
            }
            vm.prank(accounts[i]);
            governor.castVoteWithReason(proposalId, voteTypes[i], reasons[i]);
        }

        _checkVotes(proposalId, expectedVotes);
    }

    function test_Fuzz_CastVoteWithReasonAndParams(
        uint16[3] memory shareAmounts,
        uint8[3] memory voteTypes,
        string[3] memory reasons,
        bytes[3] memory params
    )
        public
    {
        (address payable[3] memory accounts, uint256 proposalId, uint256[3] memory expectedVotes) =
            _setupVotes(shareAmounts, voteTypes);

        for (uint256 i = 0; i < accounts.length; i++) {
            if (voteTypes[i] > maxVoteType) {
                vm.expectRevert(IProposalVoting.GovernorInvalidVoteValue.selector);
            } else {
                vm.expectEmit(true, true, false, true, address(governor));
                if (params[i].length > 0) {
                    emit IProposalVoting.VoteCastWithParams(
                        accounts[i], proposalId, voteTypes[i], shareAmounts[i], reasons[i], params[i]
                    );
                } else {
                    emit IProposalVoting.VoteCast(accounts[i], proposalId, voteTypes[i], shareAmounts[i], reasons[i]);
                }
            }
            vm.prank(accounts[i]);
            governor.castVoteWithReasonAndParams(proposalId, voteTypes[i], reasons[i], params[i]);
        }

        _checkVotes(proposalId, expectedVotes);
    }
}
