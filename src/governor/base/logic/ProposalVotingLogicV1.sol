// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {GovernorBaseLogicV1} from "./GovernorBaseLogicV1.sol";
import {IGovernorBase} from "../../interfaces/IGovernorBase.sol";
import {IProposalVoting} from "../../interfaces/IProposalVoting.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {BasisPoints} from "src/libraries/BasisPoints.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title ProposalVotingLogicV1
 * @author Ben Jett - @BCJdevelopment
 * @notice An external library with the main proposal voting and deadline extension logic (for reducing code size)
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

    struct DeadlineData {
        uint64 originalDeadline;
        uint64 extendedBy;
        uint64 currentDeadline;
        bool quorumReached;
    }

    uint256 internal constant _MAX_PERCENT = 100;
    uint256 internal constant _MIN_PERCENT_MAJORITY = 50;
    uint256 internal constant _MAX_PERCENT_MAJORITY = 66;

    uint256 private constant MIN_PERCENT_DECAY = 1;
    /// @notice Maximum percent decay
    uint256 private constant MAX_PERCENT_DECAY = 100;

    uint256 private constant MASK_UINT64 = 0xffffffffffffffff;
    uint256 private constant MASK_UINT8 = 0xff;

    /// @dev The fraction multiple used in the vote weight calculation
    uint256 private constant FRACTION_MULTIPLE = 1000;

    /// @dev Max 1.25 multiple on the vote weight
    uint256 private constant FRACTION_MULTIPLE_MAX = FRACTION_MULTIPLE * 5 / 4;

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

    /// @custom:storage-location erc7201:ProposalDeadlineExtensions.Storage
    struct ProposalDeadlineExtensionsStorage {
        // The max extension period for any given proposal
        uint64 _maxDeadlineExtension;
        // The base extension period for deadline extension calculations
        uint64 _baseDeadlineExtension;
        // Bbase extension amount decays by {percentDecay()} every period
        uint64 _decayPeriod;
        uint8 _percentDecay;
        // Tracking the deadlines for a proposal
        mapping(uint256 => DeadlineData) _deadlineDatas;
    }

    // keccak256(abi.encode(uint256(keccak256("ProposalDeadlineExtensions.Storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant PROPOSAL_DEADLINE_EXTENSIONS_STORAGE =
        0xae976891f3433ecd54a96b3f554eee56d31b6f881a11bab3b6460b6c2f3ce200;

    function _getProposalDeadlineExtensionsStorage()
        private
        pure
        returns (ProposalDeadlineExtensionsStorage storage $)
    {
        assembly {
            $.slot := PROPOSAL_DEADLINE_EXTENSIONS_STORAGE
        }
    }

    function setUp(IProposalVoting.ProposalVotingInit memory init) public {
        setPercentMajority(init.percentMajority);
        setQuorumBps(init.quorumBps);

        setMaxDeadlineExtension(init.maxDeadlineExtension);
        setBaseDeadlineExtension(init.baseDeadlineExtension);
        setExtensionDecayPeriod(init.decayPeriod);
        setExtensionPercentDecay(init.percentDecay);
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
        // toBps() checks for out of range BPS value
        $._quorumBpsCheckpoints.push(GovernorBaseLogicV1._clock(), newQuorumBps.toBps());
        emit IProposalVoting.QuorumBpsUpdate(oldQuorumBps, newQuorumBps);
    }

    /**
     * @dev Returns true if a quorum has been reached based on the amount of votes cast for a proposal.
     */
    function _quorumReached(uint256 proposalId) internal view returns (bool isQuorumReached) {
        ProposalVote storage proposalVote = _getProposalVotingStorage()._proposalVotes[proposalId];

        // We use unchecked, expected behavior is no possible overflow, as each account can only vote once
        unchecked {
            isQuorumReached = _quorum(GovernorBaseLogicV1._proposalSnapshot(proposalId))
                <= proposalVote.forVotes + proposalVote.abstainVotes;
        }
    }

    /**
     * @dev In this module, the percentage of forVotes must be greater than the percent majortity value at the proposal
     * snapshot.
     */
    function _voteSucceeded(uint256 proposalId) internal view returns (bool) {
        uint256 percentToSucceed = _percentMajority(GovernorBaseLogicV1._proposalSnapshot(proposalId));
        ProposalVote storage _proposalVote = _getProposalVoteStorageRef(proposalId);
        uint256 againstVotes = _proposalVote.againstVotes;
        uint256 forVotes = _proposalVote.forVotes;

        /**
         * (percentToSucceed / 100) < forVotes / (forVotes + againstVotes)
         * which becomes...
         * percentToSucceed < (forVotes * 100) / (forVotes + againstVotes)
         */

        // Avoid possible divide by zero error
        if (againstVotes == 0) {
            return forVotes > 0;
        }

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

        uint256 percentToSucceed = _percentMajority(GovernorBaseLogicV1._proposalSnapshot(proposalId));

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
        GovernorBaseLogicV1._validateStateBitmap(
            proposalId, GovernorBaseLogicV1._encodeStateBitmap(IGovernorBase.ProposalState.Active)
        );

        IGovernorBase.ProposalCore storage proposal = GovernorBaseLogicV1._getProposalsStorage()._proposals[proposalId];

        weight = GovernorBaseLogicV1._getVotes(account, proposal.voteStart, params);
        _countVote(proposalId, account, support, weight, params);

        processDeadlineExtensionOnVote(proposalId, weight);

        if (params.length == 0) {
            emit IProposalVoting.VoteCast(account, proposalId, support, weight, reason);
        } else {
            emit IProposalVoting.VoteCastWithParams(account, proposalId, support, weight, reason, params);
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
        DEADLINE EXTENSIONS
    //////////////////////////////////////////////////////////////////////////*/

    function _proposalDeadline(uint256 proposalId) internal view returns (uint256) {
        uint256 currentDeadline = _getProposalDeadlineExtensionsStorage()._deadlineDatas[proposalId].currentDeadline;
        // If uninitialized (no votes cast yet), return the original proposal deadline
        if (currentDeadline == 0) {
            return _originalProposalDeadline(proposalId);
        }
        return currentDeadline;
    }

    function _originalProposalDeadline(uint256 proposalId) internal view returns (uint256) {
        return GovernorBaseLogicV1._proposalDeadline(proposalId);
    }

    function _maxDeadlineExtension() internal view returns (uint256) {
        return _getProposalDeadlineExtensionsStorage()._maxDeadlineExtension;
    }

    function setMaxDeadlineExtension(uint256 newMaxDeadlineExtension) public {
        ProposalDeadlineExtensionsStorage storage $ = _getProposalDeadlineExtensionsStorage();
        emit IProposalVoting.MaxDeadlineExtensionUpdate($._maxDeadlineExtension, newMaxDeadlineExtension);
        $._maxDeadlineExtension = newMaxDeadlineExtension.toUint64();
    }

    function _baseDeadlineExtension() internal view returns (uint256) {
        return _getProposalDeadlineExtensionsStorage()._baseDeadlineExtension;
    }

    function setBaseDeadlineExtension(uint256 newBaseDeadlineExtension) public {
        ProposalDeadlineExtensionsStorage storage $ = _getProposalDeadlineExtensionsStorage();
        emit IProposalVoting.BaseDeadlineExtensionUpdate($._baseDeadlineExtension, newBaseDeadlineExtension);
        $._baseDeadlineExtension = newBaseDeadlineExtension.toUint64();
    }

    function _extensionDecayPeriod() internal view returns (uint256) {
        return _getProposalDeadlineExtensionsStorage()._decayPeriod;
    }

    function setExtensionDecayPeriod(uint256 newDecayPeriod) public {
        if (newDecayPeriod == 0) {
            revert IProposalVoting.GovernorExtensionDecayPeriodCannotBeZero();
        }

        ProposalDeadlineExtensionsStorage storage $ = _getProposalDeadlineExtensionsStorage();
        emit IProposalVoting.ExtensionDecayPeriodUpdate($._decayPeriod, newDecayPeriod);
        $._decayPeriod = newDecayPeriod.toUint64();
    }

    function _extensionPercentDecay() internal view returns (uint256) {
        return _getProposalDeadlineExtensionsStorage()._percentDecay;
    }

    function setExtensionPercentDecay(uint256 newPercentDecay) public {
        if (newPercentDecay < MIN_PERCENT_DECAY || newPercentDecay > MAX_PERCENT_DECAY) {
            revert IProposalVoting.GovernorExtensionPercentDecayOutOfRange(MIN_PERCENT_DECAY, MAX_PERCENT_DECAY);
        }

        ProposalDeadlineExtensionsStorage storage $ = _getProposalDeadlineExtensionsStorage();
        emit IProposalVoting.ExtensionPercentDecayUpdate($._percentDecay, newPercentDecay);
        // SafeCast unnecessary here as long as the MAX_PERCENT_DECAY is less than type(uint8).max
        $._percentDecay = uint8(newPercentDecay);
    }

    function processDeadlineExtensionOnVote(uint256 proposalId, uint256 voteWeight) public {
        ProposalDeadlineExtensionsStorage storage $ = _getProposalDeadlineExtensionsStorage();

        // Copy the packed settings to stack for reads
        bytes32 packedSettingsSlot;
        assembly {
            packedSettingsSlot := sload($.slot)
        }

        // Grab the max deadline extension
        uint256 maxDeadlineExtension_;
        assembly {
            maxDeadlineExtension_ := and(MASK_UINT64, packedSettingsSlot)
        }

        // If maxDeadlineExtension is set to zero, then no deadline updates needed, skip the rest to save gas
        if (maxDeadlineExtension_ == 0) {
            return;
        }

        // Retrieve the existing deadline data for this proposal
        DeadlineData memory dd = $._deadlineDatas[proposalId];

        // If extension is already maxxed out, no further updates needed
        if (dd.extendedBy >= maxDeadlineExtension_) {
            return;
        }

        // If quorum wasn't reached last time, check again
        if (!dd.quorumReached) {
            dd.quorumReached = ProposalVotingLogicV1._quorumReached(proposalId);
            // If quorum still hasn't been reached, skip the calculation and return
            if (!dd.quorumReached) {
                return;
            }
        }

        // Initialize the rest of the struct if it hasn't been initialized yet
        if (dd.originalDeadline == 0) {
            // Assumes safe conversion, uint64 should be large enough for either block numbers or timestamps in seconds
            dd.originalDeadline = uint64(_originalProposalDeadline(proposalId));
            dd.currentDeadline = dd.originalDeadline;
        }

        // Initialize extendMultiple
        uint256 extendMultiple;

        uint256 currentTimepoint = GovernorBaseLogicV1._clock();

        /**
         * Save gas with unchecked, this is ok because all overflow/underflow checks are performed in the code here:
         * - If the currentDeadline wasn't larger than the currentTimepoint, the vote wouldn't be allowed to be cast
         * - Only subtracts the originalDeadline from the currentTimepoint if the currentTimepoint is larger
         * - Only subtracts the distanceFromDeadline from the extend amount if extend amount is larger
         *
         * Additionally, this block scopes the storage variables to avoid "stack too deep" errors
         */
        unchecked {
            // Read rest of settings from the packed slot
            uint256 baseDeadlineExtension_;
            uint256 decayPeriod_;
            uint256 percentDecay_;
            assembly {
                baseDeadlineExtension_ := and(MASK_UINT64, shr(64, packedSettingsSlot))
                decayPeriod_ := and(MASK_UINT64, shr(128, packedSettingsSlot))
                percentDecay_ := and(MASK_UINT8, shr(192, packedSettingsSlot))
            }

            // Get the current distance from the deadline
            uint256 distanceFromDeadline = dd.currentDeadline - currentTimepoint;

            // We can return if we are outside the range of the base extension amount (since it gets subtracted out)
            if (baseDeadlineExtension_ < distanceFromDeadline) {
                return;
            }

            // Extend amount decays past the original deadline
            if (currentTimepoint > dd.originalDeadline) {
                uint256 periodsElapsed = (currentTimepoint - dd.originalDeadline) / decayPeriod_;
                uint256 extend = (baseDeadlineExtension_ * (MAX_PERCENT_DECAY - percentDecay_) ** periodsElapsed)
                    / (100 ** periodsElapsed);
                // Check again for distance from the deadline. If extend is too small, just return.
                if (extend < distanceFromDeadline) {
                    return;
                }
                extendMultiple = extend - distanceFromDeadline;
            } else {
                extendMultiple = baseDeadlineExtension_ - distanceFromDeadline;
            }
        }

        // We include a FRACTION_MULTIPLE that we later divide back out to circumvent integer division issues
        uint256 deadlineExtension = extendMultiple
            * Math.min(
                FRACTION_MULTIPLE_MAX,
                // Add 1 to avoid divide by zero error
                (voteWeight * FRACTION_MULTIPLE / (ProposalVotingLogicV1._voteMargin(proposalId) + 1))
            ) / FRACTION_MULTIPLE;

        // Only need to extend and emit if the extension is greater than 0
        if (deadlineExtension > 0) {
            // Update extended by with the extension value, maxing out at the max deadline extension
            dd.extendedBy += SafeCast.toUint64(Math.max(deadlineExtension, maxDeadlineExtension_));
            // Update the new deadline
            dd.currentDeadline = dd.originalDeadline + dd.extendedBy;

            // Set in storage
            $._deadlineDatas[proposalId] = dd;

            // Emit the event
            emit IProposalVoting.ProposalDeadlineExtended(proposalId, dd.currentDeadline);
        }
    }
}
