// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {GovernorBase} from "./GovernorBase.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title ProposalDeadlineExtensions
 *
 * @dev A module to extend the deadline for controversial votes. The extension amount for each vote is dynamically
 * computed, taking several parameters into account, such as:
 * - Only extends the deadline if a quorum has been reached.
 * - Only extends if the vote is taking place close to the current deadline.
 * - If the vote is particularly influential to the outcome of the vote, this will weight towards a larger extension.
 * - If the vote takes place close to the current deadline, this will also weight towards a longer extension.
 * - The deadline extension amount decays exponentially as the proposal moves further past its original deadline.
 *
 * This is designed as a dynamic protection mechanism against "Vote Sniping," where the outcome of a low activity
 * proposal is flipped at the last minute by a heavy swing vote, without leaving time for additional voters to react.
 *
 * The decay function of the extensions is designed to prevent DoS by constant vote updates.
 *
 * Through the governance process, the DAO can set the baseDeadlineExtension, the decayPeriod, and the percentDecay
 * values. This allows fine-tuning the exponential decay of the baseDeadlineExtension amount as a vote moves past the
 * original proposal deadline (to prevent votes from being filibustered forever by constant voting).
 *
 * The exponential decay of the baseDeadlineExtension follows the following formula:
 *
 * E = [ baseDeadlineExtension * ( 100 - percentDecay)**P ] / [ 100**P ]
 *
 * Where P = distancePastDeadline / decayPeriod = ( currentTimepoint - originalDeadline ) / decayPeriod
 *
 * Notably, if the original deadline has not been reached yet, then E = baseDeadlineExtension
 *
 * Finally, the actual extension amount follows the following formula for each cast vote:
 *
 * deadlineExtension = ( E - distanceFromDeadline ) * min(1.25, [ voteWeight / ( abs(ForVotes - AgainstVotes) + 1 ) ])
 *
 * @author Ben Jett - @BCJdevelopment
 */
abstract contract ProposalDeadlineExtensions is GovernorBase {
    struct DeadlineData {
        uint64 originalDeadline;
        uint64 extendedBy;
        uint64 currentDeadline;
        bool quorumReached;
    }

    uint256 private constant MIN_PERCENT_DECAY = 1;
    /// @notice Maximum percent decay
    uint256 private constant MAX_PERCENT_DECAY = 100;

    /// @custom:storage-location erc7201:ProposalDeadlineExtensions.Storage
    struct ProposalDeadlineExtensionsStorage {
        // The max extension period for any given proposal
        uint64 _maxDeadlineExtension;
        // The base extension period for deadline extension calculations
        uint64 _baseDeadlineExtension;
        // Bbase extension amount decays by {percentDecay()} every period
        uint64 _decayPeriod;
        // Store inverted (100% - percentDecay), saves a subtract op
        uint64 _percentDecay;
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

    /// @dev The fraction multiple used in the vote weight calculation
    uint256 private constant FRACTION_MULTIPLE = 1000;
    uint256 private constant FRACTION_MULTIPLE_MAX = FRACTION_MULTIPLE * 5 / 4; // Max 1.25 multiple on the vote weight

    event ProposalDeadlineExtended(uint256 indexed proposalId, uint256 extendedDeadline);
    event MaxDeadlineExtensionSet(uint256 oldMaxDeadlineExtension, uint256 newMaxDeadlineExtension);
    event BaseDeadlineExtensionSet(uint256 oldBaseDeadlineExtension, uint256 newBaseDeadlineExtension);
    event ExtensionDecayPeriodSet(uint256 oldDecayPeriod, uint256 newDecayPeriod);
    event ExtensionPercentDecaySet(uint256 oldPercentDecay, uint256 newPercentDecay);

    error ExtensionDecayPeriodCannotBeZero();
    error ExtensionPercentDecayOutOfRange(uint256 min, uint256 max);

    function __ProposalDeadlineExtensions_init(
        uint256 maxDeadlineExtension_,
        uint256 baseDeadlineExtension_,
        uint256 decayPeriod_,
        uint256 percentDecay_
    )
        internal
        virtual
        onlyInitializing
    {
        _setMaxDeadlineExtension(maxDeadlineExtension_);
        _setBaseDeadlineExtension(baseDeadlineExtension_);
        _setExtensionDecayPeriod(decayPeriod_);
        _setExtensionPercentDecay(percentDecay_);
    }

    /**
     * @dev We override to provide the extended deadline (if applicable)
     */
    function proposalDeadline(uint256 proposalId) public view virtual override returns (uint256) {
        uint256 currentDeadline = _getProposalDeadlineExtensionsStorage()._deadlineDatas[proposalId].currentDeadline;
        // If uninitialized (no votes cast yet), return the original proposal deadline
        if (currentDeadline == 0) {
            return super.proposalDeadline(proposalId);
        }
        return currentDeadline;
    }

    function proposalOriginalDeadline(uint256 proposalId) public view virtual returns (uint256) {
        return GovernorBase.proposalDeadline(proposalId);
    }

    /**
     * @notice The current max extension period for any given proposal. The voting period cannot be extended past the
     * original deadline more than this amount. DAOs can set this to zero for no extensions whatsoever.
     */
    function maxDeadlineExtension() public view returns (uint256) {
        return _getProposalDeadlineExtensionsStorage()._maxDeadlineExtension;
    }

    function setMaxDeadlineExtension(uint256 newMaxDeadlineExtension) public virtual onlyGovernance {
        _setMaxDeadlineExtension(newMaxDeadlineExtension);
    }

    function _setMaxDeadlineExtension(uint256 newMaxDeadlineExtension) internal virtual {
        ProposalDeadlineExtensionsStorage storage $ = _getProposalDeadlineExtensionsStorage();
        emit MaxDeadlineExtensionSet($._maxDeadlineExtension, newMaxDeadlineExtension);
        // SafeCast unnecessary here as long as the MAX_BASE_DEADLINE_EXTENSION is less than type(uint64).max
        $._maxDeadlineExtension = uint64(newMaxDeadlineExtension);
    }

    /**
     * @notice The base extension period used in the deadline extension calculations. This amount by {percentDecay} for
     * every {decayPeriod} past the original proposal deadline.
     */
    function baseDeadlineExtension() public view virtual returns (uint256) {
        return _getProposalDeadlineExtensionsStorage()._baseDeadlineExtension;
    }

    function setBaseDeadlineExtension(uint256 newBaseDeadlineExtension) public virtual onlyGovernance {
        _setBaseDeadlineExtension(newBaseDeadlineExtension);
    }

    function _setBaseDeadlineExtension(uint256 newBaseDeadlineExtension) internal virtual {
        ProposalDeadlineExtensionsStorage storage $ = _getProposalDeadlineExtensionsStorage();
        emit BaseDeadlineExtensionSet($._baseDeadlineExtension, newBaseDeadlineExtension);
        // SafeCast unnecessary here as long as the MAX_BASE_DEADLINE_EXTENSION is less than type(uint64).max
        $._baseDeadlineExtension = uint64(newBaseDeadlineExtension);
    }

    /**
     * @notice The base extension period decays by {percentDecay} for every period set by this parameter. DAOs should be
     * sure to set this period in accordance with their clock mode.
     */
    function extensionDecayPeriod() public view virtual returns (uint256) {
        return _getProposalDeadlineExtensionsStorage()._decayPeriod;
    }

    function setExtensionDecayPeriod(uint256 newDecayPeriod) public virtual onlyGovernance {
        _setExtensionDecayPeriod(newDecayPeriod);
    }

    function _setExtensionDecayPeriod(uint256 newDecayPeriod) internal virtual {
        if (newDecayPeriod == 0) {
            revert ExtensionDecayPeriodCannotBeZero();
        }

        ProposalDeadlineExtensionsStorage storage $ = _getProposalDeadlineExtensionsStorage();
        emit ExtensionDecayPeriodSet($._decayPeriod, newDecayPeriod);
        // SafeCast unnecessary here as long as the MAX_DECAY_PERIOD is less than type(uint64).max
        $._decayPeriod = uint64(newDecayPeriod);
    }

    /**
     * @notice The percentage that the base extension period decays by for every {decayPeriod}.
     */
    function extensionPercentDecay() public view virtual returns (uint256) {
        return _getProposalDeadlineExtensionsStorage()._percentDecay;
    }

    function setExtensionPercentDecay(uint256 newPercentDecay) public virtual onlyGovernance {
        _setExtensionPercentDecay(newPercentDecay);
    }

    function _setExtensionPercentDecay(uint256 newPercentDecay) internal virtual {
        if (newPercentDecay < MIN_PERCENT_DECAY || newPercentDecay > MAX_PERCENT_DECAY) {
            revert ExtensionPercentDecayOutOfRange(MIN_PERCENT_DECAY, MAX_PERCENT_DECAY);
        }

        ProposalDeadlineExtensionsStorage storage $ = _getProposalDeadlineExtensionsStorage();
        emit ExtensionPercentDecaySet($._percentDecay, newPercentDecay);
        // SafeCast unnecessary here as long as the MAX_PERCENT_DECAY is less than type(uint64).max
        $._percentDecay = uint64(newPercentDecay);
    }

    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    )
        internal
        virtual
        override
        returns (uint256)
    {
        uint256 voteWeight = super._castVote(proposalId, account, support, reason, params);

        ProposalDeadlineExtensionsStorage storage $ = _getProposalDeadlineExtensionsStorage();

        // Grab the max deadline extension
        uint256 maxDeadlineExtension_ = $._maxDeadlineExtension;

        // If maxDeadlineExtension is set to zero, then no deadline updates needed, skip the rest to save gas
        if (maxDeadlineExtension_ == 0) {
            return voteWeight;
        }

        // Retrieve the existing deadline data for this proposal
        DeadlineData memory dd = $._deadlineDatas[proposalId];

        // If extension is already maxxed out, no further updates needed
        if (dd.extendedBy >= maxDeadlineExtension_) return voteWeight;

        // If quorum wasn't reached last time, check again
        if (!dd.quorumReached) {
            dd.quorumReached = _quorumReached(proposalId);
            // If quorum still hasn't been reached, skip the calculation and return
            if (!dd.quorumReached) return voteWeight;
        }

        // Initialize the rest of the struct if it hasn't been initialized yet
        if (dd.originalDeadline == 0) {
            // Assumes safe conversion, uint64 should be large enough for either block numbers or timestamps in seconds
            dd.originalDeadline = uint64(GovernorBase.proposalDeadline(proposalId));
            dd.currentDeadline = dd.originalDeadline;
        }

        // Initialize extendMultiple
        uint256 extendMultiple;

        uint256 currentTimepoint = clock();

        /**
         * Save gas with unchecked, this is ok because all overflow/underflow checks are performed in the code here:
         * - If the currentDeadline wasn't larger than the currentTimepoint, the vote wouldn't be allowed to be cast
         * - Only subtracts the originalDeadline from the currentTimepoint if the currentTimepoint is larger
         * - Only subtracts the distanceFromDeadline from the extend amount if extend amount is larger
         *
         * Additionally, this block scopes the storage variables to avoid "stack too deep" errors
         */
        unchecked {
            // Read all three at once to reduce storage reads
            uint256 baseDeadlineExtension_ = $._baseDeadlineExtension;
            uint256 decayPeriod_ = $._decayPeriod;
            uint256 percentDecay_ = $._percentDecay;

            // Get the current distance from the deadline
            uint256 distanceFromDeadline = dd.currentDeadline - currentTimepoint;

            // We can return if we are outside the range of the base extension amount (since it gets subtracted out)
            if (baseDeadlineExtension_ < distanceFromDeadline) return voteWeight;

            // Extend amount decays past the original deadline
            if (currentTimepoint > dd.originalDeadline) {
                uint256 periodsElapsed = (currentTimepoint - dd.originalDeadline) / decayPeriod_;
                uint256 extend = (baseDeadlineExtension_ * (MAX_PERCENT_DECAY - percentDecay_) ** periodsElapsed)
                    / (100 ** periodsElapsed);
                // Check again for distance from the deadline. If extend is too small, just return.
                if (extend < distanceFromDeadline) return voteWeight;
                extendMultiple = extend - distanceFromDeadline;
            } else {
                extendMultiple = baseDeadlineExtension_ - distanceFromDeadline;
            }
        }

        // We include a FRACTION_MULTIPLE that we later divide back out to circumvent integer division issues
        uint256 deadlineExtension = extendMultiple
            * Math.min(
                FRACTION_MULTIPLE_MAX,
                (voteWeight * FRACTION_MULTIPLE / (_voteMargin(proposalId) + 1)) // Add 1 to avoid divide by zero error
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
            emit ProposalDeadlineExtended(proposalId, dd.currentDeadline);
        }

        return voteWeight;
    }
}
