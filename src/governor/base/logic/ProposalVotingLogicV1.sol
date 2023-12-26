// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {GovernorBaseLogicV1} from "./GovernorBaseLogicV1.sol";
import {ProposalsLogicV1} from "./ProposalsLogicV1.sol";
import {IProposals} from "../../interfaces/IProposals.sol";
import {IProposalVoting} from "../../interfaces/IProposalVoting.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {BasisPoints} from "src/libraries/BasisPoints.sol";

/**
 * @title ProposalVotingLogicV1
 * @author Ben Jett - @BCJdevelopment
 * @notice An external library with the main proposal voting logic (for reducing code size)
 * @dev Some functions are internal, meaning they will still be included in a contract's code if the contract makes use
 * of these functions. While this leads to some bytecode duplication across contracts/libraries, it also saves on gas by
 * avoiding extra DELEGATECALL's in some cases.
 */
library ProposalVotingLogicV1 {
    using SafeCast for *;
    using Checkpoints for Checkpoints.Trace208;
    using BasisPoints for uint256;

    struct ProposalVote {
        uint256 againstVotes;
        uint256 forVotes;
        uint256 abstainVotes;
        mapping(address => bool) hasVoted;
    }



    uint256 internal constant _MAX_PERCENT = 100;
    uint256 internal constant _MIN_PERCENT_MAJORITY = 50;
    uint256 internal constant _MAX_PERCENT_MAJORITY = 66;

    /// @custom:storage-location erc7201:ProposalVoting.Storage
    struct ProposalVotingStorage {
        Checkpoints.Trace208 _percentMajorityCheckpoints;
        Checkpoints.Trace208 _quorumBpsCheckpoints;
        mapping(uint256 => ProposalVote) _proposalVotes;
    }

    // keccak256(abi.encode(uint256(keccak256("ProposalVoting.Storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant PROPOSAL_VOTING_STORAGE =
        0x1dcf31df974e58851e6e8e0a154625c7bd3193e7770266820e15815a6252cc00;

    function _getProposalVotingStorage() private pure returns (ProposalVotingStorage storage $) {
        assembly {
            $.slot := PROPOSAL_VOTING_STORAGE
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
        VOTE COUNTING
    //////////////////////////////////////////////////////////////////////////*/

    function _hasVoted(uint256 proposalId, address account) internal view returns (bool) {
        return _getProposalVotingStorage()._proposalVotes[proposalId].hasVoted[account];
    }

    function _proposalVotes(uint256 proposalId)
        internal
        view
        returns (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes)
    {
        ProposalVote storage _proposalVote = _getProposalVoteStorageRef(proposalId);
        return (_proposalVote.againstVotes, _proposalVote.forVotes, _proposalVote.abstainVotes);
    }

    /// @dev Internal access to ProposalVote storage for a proposalId
    function _getProposalVoteStorageRef(uint256 proposalId) internal view returns (ProposalVote storage proposalVote) {
        proposalVote = _getProposalVotingStorage()._proposalVotes[proposalId];
    }

    /**
     * @dev Register a vote for `proposalId` by `account` with `support`, `weight`, and optional `params`. In this
     * module, the support follows the `VoteType` enum.
     */
    function _countVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 weight,
        bytes memory /*params*/
    )
        internal
    {
        ProposalVote storage proposalVote = _getProposalVotingStorage()._proposalVotes[proposalId];

        if (proposalVote.hasVoted[account]) {
            revert IProposalVoting.GovernorVoteAlreadyCast(proposalId, account);
        }
        proposalVote.hasVoted[account] = true;

        // We use unchecked, expected behavior is no possible overflow, as each account can only vote once
        unchecked {
            if (support == uint8(IProposalVoting.VoteType.Against)) {
                proposalVote.againstVotes += weight;
            } else if (support == uint8(IProposalVoting.VoteType.For)) {
                proposalVote.forVotes += weight;
            } else if (support == uint8(IProposalVoting.VoteType.Abstain)) {
                proposalVote.abstainVotes += weight;
            } else {
                revert IProposalVoting.GovernorInvalidVoteValue();
            }
        }
    }

    function _percentMajority(uint256 timepoint) internal view returns (uint256) {
        ProposalVotingStorage storage $ = _getProposalVotingStorage();

        // Optimistic search, check the latest checkpoint
        (bool exists, uint256 _key, uint256 _value) = $._percentMajorityCheckpoints.latestCheckpoint();
        if (exists && _key <= timepoint) {
            return _value;
        }

        // Otherwise, do the binary search
        return $._percentMajorityCheckpoints.upperLookupRecent(timepoint.toUint48());
    }

    function setPercentMajority(uint256 newPercentMajority) public {
        if (newPercentMajority < _MIN_PERCENT_MAJORITY || newPercentMajority > _MAX_PERCENT_MAJORITY) {
            revert IProposalVoting.GovernorPercentMajorityOutOfRange(_MIN_PERCENT_MAJORITY, _MAX_PERCENT_MAJORITY);
        }

        ProposalVotingStorage storage $ = _getProposalVotingStorage();
        uint256 oldPercentMajority = $._percentMajorityCheckpoints.latest();

        // Set new percent majority for future proposals
        $._percentMajorityCheckpoints.push(GovernorBaseLogicV1._clock(), uint208(newPercentMajority));
        emit IProposalVoting.PercentMajorityUpdate(oldPercentMajority, newPercentMajority);
    }

    function _quorum(uint256 timepoint) internal view returns (uint256 quorum_) {
        // Check for zero bps to save gas
        uint256 quorumBps_ = _quorumBps(timepoint);
        if (quorumBps_ == 0) {
            return quorum_;
        }

        // NOTE: We don't need to check for overflow AS LONG AS the max supply of the token is <= type(uint224).max
        quorum_ = GovernorBaseLogicV1._token().getPastTotalSupply(timepoint).bpsUnchecked(quorumBps_);
    }

    function _quorumBps(uint256 timepoint) internal view returns (uint256) {
        ProposalVotingStorage storage $ = _getProposalVotingStorage();

        // Optimistic search, check the latest checkpoint
        (bool exists, uint256 _key, uint256 _value) = $._quorumBpsCheckpoints.latestCheckpoint();
        if (exists && _key <= timepoint) {
            return _value;
        }

        // Otherwise, do the binary search
        return $._quorumBpsCheckpoints.upperLookupRecent(timepoint.toUint48());
    }

    function setQuorumBps(uint256 newQuorumBps) public {
        ProposalVotingStorage storage $ = _getProposalVotingStorage();
        uint256 oldQuorumBps = $._quorumBpsCheckpoints.latest();

        // Set new quorum for future proposals
        $._quorumBpsCheckpoints.push(GovernorBaseLogicV1._clock(), newQuorumBps.toBps()); // toBps() checks for out of range BPS value
        emit IProposalVoting.QuorumBpsUpdate(oldQuorumBps, newQuorumBps);
    }

    /**
     * @dev Returns true if a quorum has been reached based on the amount of votes cast for a proposal.
     */
    function _quorumReached(uint256 proposalId) internal view returns (bool isQuorumReached) {
        ProposalVote storage proposalVote = _getProposalVotingStorage()._proposalVotes[proposalId];

        // We use unchecked, expected behavior is no possible overflow, as each account can only vote once
        unchecked {
            isQuorumReached = _quorum(ProposalsLogicV1._proposalSnapshot(proposalId))
                <= proposalVote.forVotes + proposalVote.abstainVotes;
        }
    }

    /**
     * @dev In this module, the percentage of forVotes must be greater than the percent majortity value at the proposal
     * snapshot.
     */
    function _voteSucceeded(uint256 proposalId) internal view returns (bool) {
        uint256 percentToSucceed = _percentMajority(ProposalsLogicV1._proposalSnapshot(proposalId));
        ProposalVote storage _proposalVote = _getProposalVoteStorageRef(proposalId);
        uint256 againstVotes = _proposalVote.againstVotes;
        uint256 forVotes = _proposalVote.forVotes;

        /**
         * (percentToSucceed / 100) < forVotes / (forVotes + againstVotes)
         * which becomes...
         * percentToSucceed < (forVotes * 100) / (forVotes + againstVotes)
         */

        uint256 numerator = forVotes * _MAX_PERCENT;
        uint256 denominator = againstVotes + forVotes;

        // Find the division result.
        uint256 divResult = numerator / denominator;
        // If greater than the minimum percent, then it succeeded
        if (divResult > percentToSucceed) return true;
        // If equal, check the remainder
        if (divResult == percentToSucceed) {
            uint256 remainder = numerator % denominator;
            // If there is a remainder, then it succeeded
            if (remainder > 0) return true;
        }
        // Otherwise, return false
        return false;
    }

    /**
     * @dev The spread between the for votes and the against votes, calculated as the distance of the current forVotes
     * from the tipping point number of forVotes required to reverse the current voting success of the proposal.
     */
    function _voteMargin(uint256 proposalId) internal view returns (uint256) {
        ProposalVote storage _proposalVote = _getProposalVoteStorageRef(proposalId);
        uint256 againstVotes = _proposalVote.againstVotes;
        uint256 forVotes = _proposalVote.forVotes;

        // If the againstVotes is zero, then the margin is just the forVotes
        if (againstVotes == 0) {
            return forVotes;
        }

        uint256 percentToSucceed = _percentMajority(ProposalsLogicV1._proposalSnapshot(proposalId));

        /**
         * forVotesToSucceed / (forVotesToSucceed + againstVotes) = percentToSucceed / 100
         * which after some rearranging becomes...
         * forVotesToSucceed = (percentToSucceed * againstVotes) / (100 - percentToSucceed)
         */

        uint256 numerator = percentToSucceed * againstVotes;
        uint256 denominator = _MAX_PERCENT - percentToSucceed;
        uint256 forVotesToTipScales = numerator / denominator;
        // If there is a remainder, we need to add 1 to the result
        if (numerator % denominator > 0) {
            forVotesToTipScales += 1;
        }
        return forVotes > forVotesToTipScales ? forVotes - forVotesToTipScales : forVotesToTipScales - forVotes;
    }

    /*//////////////////////////////////////////////////////////////////////////
        CASTING VOTES
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Internal vote casting mechanism: Check that the vote is pending, that it has not been cast yet, retrieve
     * voting weight using {IGovernor-getVotes} and call the {_countVote} internal function.
     *
     * Emits a {IGovernor-VoteCast} event.
     */
    function castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    )
        public
        returns (uint256 weight)
    {
        ProposalsLogicV1._validateStateBitmap(proposalId, ProposalsLogicV1._encodeStateBitmap(IProposals.ProposalState.Active));

        ProposalsLogicV1.ProposalCore storage proposal = ProposalsLogicV1._getProposalsStorage()._proposals[proposalId];

        weight = GovernorBaseLogicV1._getVotes(account, proposal.voteStart, params);
        _countVote(proposalId, account, support, weight, params);

        if (params.length == 0) {
            emit IProposalVoting.VoteCast(account, proposalId, support, weight, reason);
        } else {
            emit IProposalVoting.VoteCastWithParams(account, proposalId, support, weight, reason, params);
        }
    }
}
