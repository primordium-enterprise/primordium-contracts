// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts (last updated v4.8.0) (extensions/GovernorCountingSimple.sol)

pragma solidity ^0.8.20;

import {GovernorBase} from "./GovernorBase.sol";

/**
 * @title VoteCounting
 *
 * @dev Extension of {GovernorBase} for simple, 3 options, vote counting (Against, For, Abstain).
 *
 * @author Ben Jett - @BCJdevelopment
 */
abstract contract VoteCounting is GovernorBase {
    /**
     * @dev Supported vote types. Matches GovernorBase Bravo ordering.
     */
    enum VoteType {
        Against,
        For,
        Abstain
    }

    struct ProposalVote {
        uint256 againstVotes;
        uint256 forVotes;
        uint256 abstainVotes;
        mapping(address => bool) hasVoted;
    }

    /// @custom:storage-location erc7201:VoteCounting.Storage
    struct VoteCountingStorage {
        mapping(uint256 => ProposalVote) _proposalVotes;
    }

    // keccak256(abi.encode(uint256(keccak256("VoteCounting.Storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant VOTE_COUNTING_STORAGE = 0x16fd3682d81d1f1c054ac6f115d03ff34fa3ca070ab82bd2207eb8c3ae407200;

    function _getVoteCountingStorage() private pure returns (VoteCountingStorage storage $) {
        assembly {
            $.slot := VOTE_COUNTING_STORAGE
        }
    }

    error VoteAlreadyCast();
    error InvalidVoteValue();

    /**
     * @dev See {IGovernor-COUNTING_MODE}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "support=bravo&quorum=for,abstain";
    }

    /**
     * @dev See {IGovernor-hasVoted}.
     */
    function hasVoted(uint256 proposalId, address account) public view virtual override returns (bool) {
        return _getVoteCountingStorage()._proposalVotes[proposalId].hasVoted[account];
    }

    /**
     * @dev Accessor to the internal vote counts.
     */
    function proposalVotes(uint256 proposalId)
        public
        view
        virtual
        returns (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes)
    {
        ProposalVote storage proposalVote = _getVoteCountingStorage()._proposalVotes[proposalId];
        return (proposalVote.againstVotes, proposalVote.forVotes, proposalVote.abstainVotes);
    }

    function _proposalVote(uint256 proposalId) internal view virtual returns (ProposalVote storage proposalVote) {
        proposalVote = _getVoteCountingStorage()._proposalVotes[proposalId];
    }

    /**
     * @dev See {GovernorBase-_quorumReached}.
     */
    function _quorumReached(uint256 proposalId) internal view virtual override returns (bool) {
        ProposalVote storage proposalVote = _getVoteCountingStorage()._proposalVotes[proposalId];

        return quorum(proposalSnapshot(proposalId)) <= proposalVote.forVotes + proposalVote.abstainVotes;
    }

    /**
     * @dev See {GovernorBase-_voteSucceeded}. In this module, the forVotes must be strictly over the againstVotes.
     */
    function _voteSucceeded(uint256 proposalId) internal view virtual override returns (bool) {
        ProposalVote storage proposalVote = _getVoteCountingStorage()._proposalVotes[proposalId];

        return proposalVote.forVotes > proposalVote.againstVotes;
    }

    /**
     * @dev See {GovernorBase-_voteMargin}. In this module, the margin is just the difference between the forVotes and
     * againstVotes.
     */
    function _voteMargin(uint256 proposalId) internal view virtual override returns (uint256) {
        ProposalVote storage proposalVote = _getVoteCountingStorage()._proposalVotes[proposalId];
        uint256 forVotes = proposalVote.forVotes;
        uint256 againstVotes = proposalVote.againstVotes;
        return forVotes > againstVotes ? forVotes - againstVotes : againstVotes - forVotes;
    }

    /**
     * @dev See {GovernorBase-_countVote}. In this module, the support follows the `VoteType` enum (from GovernorBase
     * Bravo).
     */
    function _countVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 weight,
        bytes memory // params
    )
        internal
        virtual
        override
    {
        ProposalVote storage proposalVote = _getVoteCountingStorage()._proposalVotes[proposalId];

        if (proposalVote.hasVoted[account]) revert VoteAlreadyCast();
        proposalVote.hasVoted[account] = true;

        if (support == uint8(VoteType.Against)) {
            proposalVote.againstVotes += weight;
        } else if (support == uint8(VoteType.For)) {
            proposalVote.forVotes += weight;
        } else if (support == uint8(VoteType.Abstain)) {
            proposalVote.abstainVotes += weight;
        } else {
            revert InvalidVoteValue();
        }
    }
}
