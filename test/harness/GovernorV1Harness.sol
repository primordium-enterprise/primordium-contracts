// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {PrimordiumGovernorV1} from "src/governor/PrimordiumGovernorV1.sol";
import {GovernorBaseLogicV1} from "src/governor/base/logic/GovernorBaseLogicV1.sol";
import {ProposalVotingLogicV1} from "src/governor/base/logic/ProposalVotingLogicV1.sol";

contract GovernorV1Harness is PrimordiumGovernorV1 {
    function harnessFoundGovernor() public {
        GovernorBaseLogicV1._getGovernorBaseStorage()._isFounded = true;
    }

    function harnessSetQuorumBps(uint256 newQuorumBps) public {
        _setQuorumBps(newQuorumBps);
    }

    function harnessSetPercentMajority(uint256 newPercentMajority) public {
        _setPercentMajority(newPercentMajority);
    }

    function exposeQuorumReached(uint256 proposalId) public view returns (bool) {
        return ProposalVotingLogicV1._quorumReached(proposalId);
    }

    function exposeVoteSucceeded(uint256 proposalId) public view returns (bool) {
        return ProposalVotingLogicV1._voteSucceeded(proposalId);
    }

    function exposeVoteMargin(uint256 proposalId) public view returns (uint256) {
        return ProposalVotingLogicV1._voteMargin(proposalId);
    }
}