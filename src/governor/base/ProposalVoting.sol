// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {Proposals} from "./Proposals.sol";
import {IProposalVoting} from "../interfaces/IProposalVoting.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Checkpoints} from "src/libraries/Checkpoints.sol";
import {BasisPoints} from "src/libraries/BasisPoints.sol";

abstract contract ProposalVoting is
    Proposals,
    IProposalVoting
{
    using SafeCast for *;
    using Checkpoints for Checkpoints.Trace208;
    using BasisPoints for uint256;

    struct ProposalVote {
        uint256 againstVotes;
        uint256 forVotes;
        uint256 abstainVotes;
        mapping(address => bool) hasVoted;
    }

    bytes32 private immutable BALLOT_TYPEHASH =
        keccak256("Ballot(uint256 proposalId,uint8 support,address voter,uint256 nonce)");
    bytes32 private immutable EXTENDED_BALLOT_TYPEHASH = keccak256(
        "ExtendedBallot(uint256 proposalId,uint8 support,address voter,uint256 nonce,string reason,bytes params)"
    );

    uint256 private constant MAX_PERCENT = 100;
    uint256 public constant MIN_PERCENT_MAJORITY = 50;
    uint256 public constant MAX_PERCENT_MAJORITY = 66;

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

    function __ProposalVoting_init(
        uint256 percentMajority_,
        uint256 quorumBps_
    ) internal virtual onlyInitializing {
        _setPercentMajority(percentMajority_);
        _setQuorumBps(quorumBps_);
    }

    /*//////////////////////////////////////////////////////////////////////////
        VOTE COUNTING
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IProposalVoting
    function COUNTING_MODE() public pure virtual override returns (string memory) {
        return "support=bravo&quorum=for,abstain";
    }

    /// @inheritdoc IProposalVoting
    function hasVoted(uint256 proposalId, address account) public view virtual override returns (bool) {
        return _getProposalVotingStorage()._proposalVotes[proposalId].hasVoted[account];
    }

    /// @inheritdoc IProposalVoting
    function proposalVotes(uint256 proposalId)
        public
        view
        virtual
        returns (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes)
    {
        ProposalVote storage _proposalVote = _getProposalVote(proposalId);
        return (_proposalVote.againstVotes, _proposalVote.forVotes, _proposalVote.abstainVotes);
    }

    /// @dev Internal access to ProposalVote storage for a proposalId
    function _getProposalVote(uint256 proposalId) internal view virtual returns (ProposalVote storage proposalVote) {
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
        bytes memory // params
    )
        internal
        virtual
    {
        ProposalVote storage proposalVote = _getProposalVotingStorage()._proposalVotes[proposalId];

        if (proposalVote.hasVoted[account]) {
            revert GovernorVoteAlreadyCast(proposalId, account);
        }
        proposalVote.hasVoted[account] = true;

        // We use unchecked, expected behavior is no possible overflow, as each account can only vote once
        unchecked {
            if (support == uint8(VoteType.Against)) {
                proposalVote.againstVotes += weight;
            } else if (support == uint8(VoteType.For)) {
                proposalVote.forVotes += weight;
            } else if (support == uint8(VoteType.Abstain)) {
                proposalVote.abstainVotes += weight;
            } else {
                revert GovernorInvalidVoteValue();
            }
        }
    }

    /// @inheritdoc IProposalVoting
    function percentMajority(uint256 timepoint) public view virtual returns (uint256) {
        return _percentMajority(timepoint);
    }

    function _percentMajority(uint256 timepoint) internal view virtual returns (uint256) {
        ProposalVotingStorage storage $ = _getProposalVotingStorage();

        // Optimistic search, check the latest checkpoint
        (bool exists, uint256 _key, uint256 _value) = $._percentMajorityCheckpoints.latestCheckpoint();
        if (exists && _key <= timepoint) {
            return _value;
        }

        // Otherwise, do the binary search
        return $._percentMajorityCheckpoints.upperLookupRecent(timepoint.toUint48());
    }

    /// @inheritdoc IProposalVoting
    function setPercentMajority(uint256 newPercentMajority) public virtual onlyGovernance {
        _setPercentMajority(newPercentMajority);
    }

    function _setPercentMajority(uint256 newPercentMajority) internal virtual {
        if (newPercentMajority < MIN_PERCENT_MAJORITY || newPercentMajority > MAX_PERCENT_MAJORITY) {
            revert GovernorPercentMajorityOutOfRange(MIN_PERCENT_MAJORITY, MAX_PERCENT_MAJORITY);
        }

        ProposalVotingStorage storage $ = _getProposalVotingStorage();
        uint256 oldPercentMajority = $._percentMajorityCheckpoints.latest();

        // Set new percent majority for future proposals
        $._percentMajorityCheckpoints.push(clock(), uint208(newPercentMajority));

        emit PercentMajorityUpdate(oldPercentMajority, newPercentMajority);
    }

    /// @inheritdoc IProposalVoting
    function quorum(uint256 timepoint) public view virtual returns (uint256 _quorum) {
        // Check for zero bps to save gas
        uint256 _quorumBps = quorumBps(timepoint);
        if (_quorumBps == 0) {
            return _quorum;
        }

        // NOTE: We don't need to check for overflow AS LONG AS the max supply of the token is <= type(uint224).max
        _quorum = token().getPastTotalSupply(timepoint).bpsUnchecked(_quorumBps);
    }

    /// @inheritdoc IProposalVoting
    function quorumBps(uint256 timepoint) public view virtual returns (uint256) {
        ProposalVotingStorage storage $ = _getProposalVotingStorage();

        // Optimistic search, check the latest checkpoint
        (bool exists, uint256 _key, uint256 _value) = $._quorumBpsCheckpoints.latestCheckpoint();
        if (exists && _key <= timepoint) {
            return _value;
        }

        // Otherwise, do the binary search
        return $._quorumBpsCheckpoints.upperLookupRecent(timepoint.toUint48());
    }

    /// @inheritdoc IProposalVoting
    function setQuorumBps(uint256 newQuorumBps) external virtual onlyGovernance {
        _setQuorumBps(newQuorumBps);
    }

    function _setQuorumBps(uint256 newQuorumBps) internal virtual {
        ProposalVotingStorage storage $ = _getProposalVotingStorage();
        uint256 oldQuorumBps = $._quorumBpsCheckpoints.latest();

        // Set new quorum for future proposals
        $._quorumBpsCheckpoints.push(clock(), newQuorumBps.toBps()); // toBps() checks for out of range BPS value

        emit QuorumBpsUpdate(oldQuorumBps, newQuorumBps);
    }

    /**
     * @dev See {Proposals-_quorumReached}.
     */
    function _quorumReached(uint256 proposalId) internal view virtual override returns (bool isQuorumReached) {
        ProposalVote storage proposalVote = _getProposalVotingStorage()._proposalVotes[proposalId];

        // We use unchecked, expected behavior is no possible overflow, as each account can only vote once
        unchecked {
            isQuorumReached = quorum(proposalSnapshot(proposalId)) <= proposalVote.forVotes + proposalVote.abstainVotes;
        }
    }

    /**
     * @dev See {Proposals-_voteSucceeded}. In this module, the percentage of forVotes must be greater than the
     * percent majortity value at the proposal snapshot.
     */
    function _voteSucceeded(uint256 proposalId) internal view virtual override returns (bool) {
        uint256 percentToSucceed = _percentMajority(proposalSnapshot(proposalId));
        ProposalVote storage _proposalVote = _getProposalVote(proposalId);
        uint256 againstVotes = _proposalVote.againstVotes;
        uint256 forVotes = _proposalVote.forVotes;

        /**
         * (percentToSucceed / 100) < forVotes / (forVotes + againstVotes)
         * which becomes...
         * percentToSucceed < (forVotes * 100) / (forVotes + againstVotes)
         */

        uint256 numerator = forVotes * MAX_PERCENT;
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
    function _voteMargin(uint256 proposalId) internal view virtual returns (uint256) {
        ProposalVote storage _proposalVote = _getProposalVote(proposalId);
        uint256 againstVotes = _proposalVote.againstVotes;
        uint256 forVotes = _proposalVote.forVotes;

        // If the againstVotes is zero, then the margin is just the forVotes
        if (againstVotes == 0) {
            return forVotes;
        }

        uint256 percentToSucceed = _percentMajority(proposalSnapshot(proposalId));

        /**
         * forVotesToSucceed / (forVotesToSucceed + againstVotes) = percentToSucceed / 100
         * which after some rearranging becomes...
         * forVotesToSucceed = (percentToSucceed * againstVotes) / (100 - percentToSucceed)
         */

        uint256 numerator = percentToSucceed * againstVotes;
        uint256 denominator = MAX_PERCENT - percentToSucceed;
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

    /// @inheritdoc IProposalVoting
    function castVote(uint256 proposalId, uint8 support) public virtual override returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, "");
    }

    /// @inheritdoc IProposalVoting
    function castVoteWithReason(
        uint256 proposalId,
        uint8 support,
        string calldata reason
    )
        public
        virtual
        override
        returns (uint256)
    {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, reason);
    }

    /// @inheritdoc IProposalVoting
    function castVoteWithReasonAndParams(
        uint256 proposalId,
        uint8 support,
        string calldata reason,
        bytes memory params
    )
        public
        virtual
        override
        returns (uint256)
    {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, reason, params);
    }

    /// @inheritdoc IProposalVoting
    function castVoteBySig(
        uint256 proposalId,
        uint8 support,
        address voter,
        bytes memory signature
    )
        public
        virtual
        override
        returns (uint256)
    {
        bool valid = SignatureChecker.isValidSignatureNow(
            voter,
            _hashTypedDataV4(keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support, voter, _useNonce(voter)))),
            signature
        );

        if (!valid) {
            revert GovernorInvalidSignature(voter);
        }

        return _castVote(proposalId, voter, support, "");
    }

    /// @inheritdoc IProposalVoting
    function castVoteWithReasonAndParamsBySig(
        uint256 proposalId,
        uint8 support,
        address voter,
        string calldata reason,
        bytes memory params,
        bytes memory signature
    )
        public
        virtual
        override
        returns (uint256)
    {
        bool valid = SignatureChecker.isValidSignatureNow(
            voter,
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        EXTENDED_BALLOT_TYPEHASH,
                        proposalId,
                        support,
                        voter,
                        _useNonce(voter),
                        keccak256(bytes(reason)),
                        keccak256(params)
                    )
                )
            ),
            signature
        );

        if (!valid) {
            revert GovernorInvalidSignature(voter);
        }

        return _castVote(proposalId, voter, support, reason, params);
    }

    /**
     * @dev Internal vote casting mechanism: Check that the vote is pending, that it has not been cast yet, retrieve
     * voting weight using {IGovernor-getVotes} and call the {_countVote} internal function. Uses the _defaultParams().
     *
     * Emits a {IGovernor-VoteCast} event.
     */
    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason
    )
        internal
        virtual
        returns (uint256)
    {
        return _castVote(proposalId, account, support, reason, _defaultParams());
    }

    /**
     * @dev Internal vote casting mechanism: Check that the vote is pending, that it has not been cast yet, retrieve
     * voting weight using {IGovernor-getVotes} and call the {_countVote} internal function.
     *
     * Emits a {IGovernor-VoteCast} event.
     */
    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    )
        internal
        virtual
        returns (uint256 weight)
    {
        _validateStateBitmap(proposalId, _encodeStateBitmap(ProposalState.Active));

        ProposalCore storage proposal = _getProposalsStorage()._proposals[proposalId];

        weight = _getVotes(account, proposal.voteStart, params);
        _countVote(proposalId, account, support, weight, params);

        if (params.length == 0) {
            emit VoteCast(account, proposalId, support, weight, reason);
        } else {
            emit VoteCastWithParams(account, proposalId, support, weight, reason, params);
        }
    }
}