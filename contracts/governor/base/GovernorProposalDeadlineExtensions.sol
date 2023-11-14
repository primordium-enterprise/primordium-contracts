// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import "./GovernorBase.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @dev A module to extend the deadline for controversial votes. The extension amount for each vote is dynamically
 * computed, taking several parameters into account, such as:
 * - Only extends the deadline if a quorum has been reached.
 * - Only extends if the vote is taking place close to the current deadline.
 * - If the vote is particularly influential to the outcome of the vote, this will weight towards a longer deadline
 * extension.
 * - If the vote takes place close to the current deadline, this will also weight towards a longer deadline extension to
 * give other DAO members time to react.
 * - The deadline extension amount decays exponentially as the proposal moves further past its original deadline to
 * prevent infinite delays and/or DoS for the outcome.

 *
 * This is designed as a dynamic protection mechanism against "Vote Sniping," where the outcome of a low activity
 * proposal is flipped at the last minute by a heavy swing vote, without leaving time for additional voters to react.
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
 */
abstract contract GovernorProposalDeadlineExtensions is GovernorBase {

    struct DeadlineData {
        uint64 originalDeadline;
        uint64 extendedBy;
        uint64 currentDeadline;
        bool quorumReached;
    }

    /**
     * @notice The absolute max amount that the deadline can be extended by, set to approximately 2 weeks.
     */
    uint256 public immutable MAX_DEADLINE_EXTENSION;
    /**
     * @notice The maximum base extension period for extending votes, set to approximately 3 days.
     */
    uint256 public immutable MAX_BASE_DEADLINE_EXTENSION;
    /**
     * @notice The minimum base extension period for extending votes, set to approximately 6 hours.
     */
    uint256 public immutable MIN_BASE_DEADLINE_EXTENSION;
    /**
     * @notice The decay period must be greater than zero, so the minimum is 1.
     */
    uint256 public constant MIN_DECAY_PERIOD = 1;
    /**
     * @notice The maximum decay period for additional deadline extensions, set to approximately 1 day.
     */
    uint256 public immutable MAX_DECAY_PERIOD;
    /**
     * @notice The percent decay must be greater than zero, so the minimum is 1.
     */
    uint256 public constant MIN_PERCENT_DECAY = 1;
    /**
     * @notice Maximum percent decay
     */
    uint256 public constant MAX_PERCENT_DECAY = 100;

    // Setable by DAO, the max extension period for any given proposal
    uint64 private _maxDeadlineExtension;
    event MaxDeadlineExtensionSet(uint256 oldMaxDeadlineExtension, uint256 newMaxDeadlineExtension);

    // Setable by DAO, the base extension period for deadline extension calculations
    uint64 private _baseDeadlineExtension;
    event BaseDeadlineExtensionSet(uint256 oldBaseDeadlineExtension, uint256 newBaseDeadlineExtension);

    // Setable by DAO, base extension amount decays by {percentDecay()} every period
    uint64 private _decayPeriod;
    event DecayPeriodSet(uint256 oldDecayPeriod, uint256 newDecayPeriod);

    // Setable by DAO, store inverted (100% - percentDecay), saves a subtract op
    uint64 private _inversePercentDecay;
    event PercentDecaySet(uint256 oldPercentDecay, uint256 newPercentDecay);

    // Tracking the deadlines for a proposal
    mapping(uint256 => DeadlineData) private _deadlineDatas;

    /// @dev The fraction multiple used in the vote weight calculation
    uint256 private constant FRACTION_MULTIPLE = 1000;
    uint256 private constant FRACTION_MULTIPLE_MAX = FRACTION_MULTIPLE * 5 / 4; // Max 1.25 multiple on the vote weight

    event ProposalExtended(uint256 indexed proposalId, uint256 extendedDeadline);

    error MaxDeadlineExtensionTooLarge(uint256 max);
    error BaseDeadlineExtensionOutOfRange(uint256 min, uint256 max);
    error DecayPeriodOutOfRange(uint256 min, uint256 max);
    error PercentDecayOutOfRange(uint256 min, uint256 max);

    constructor() {
        // Initialize immutables based on clock (assumes seconds if not block number)
        bool usesBlockNumber = clock() == block.number;
        MAX_DEADLINE_EXTENSION = usesBlockNumber ?
            100_800 : // About 2 weeks at 12sec/block
            2 weeks;
        MAX_BASE_DEADLINE_EXTENSION = usesBlockNumber ?
            21_600 : // About 3 days at 12sec/block
            3 days;
        MIN_BASE_DEADLINE_EXTENSION = usesBlockNumber ?
            1_800 : // About 6 hours at 12sec/block
            6 hours;
        MAX_DECAY_PERIOD = usesBlockNumber ?
            7_200 : // About 1 day at 12sec/block
            1 days;
    }

    /**
     * @dev We override to provide the extended deadline (if applicable)
     */
    function proposalDeadline(uint256 proposalId) public view virtual override returns (uint256) {
        uint256 currentDeadline = _deadlineDatas[proposalId].currentDeadline;
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
        return _maxDeadlineExtension;
    }

    /**
     * @notice The base extension period used in the deadline extension calculations. This amount by {percentDecay} for
     * every {decayPeriod} past the original proposal deadline.
     */
    function baseDeadlineExtension() public view virtual returns (uint256) {
        return _baseDeadlineExtension;
    }

    /**
     * @notice The base extension period decays by {percentDecay} for every period set by this parameter. DAOs should be
     * sure to set this period in accordance with their clock mode.
     */
    function decayPeriod() public view virtual returns (uint256) {
        return _decayPeriod;
    }

    /**
     * @notice The percentage that the base extension period decays by for every {decayPeriod}.
     */
    function percentDecay() public view virtual returns (uint256) {
        return MAX_PERCENT_DECAY - _inversePercentDecay;
    }

    function updateMaxDeadlineExtension(uint256 newMaxDeadlineExtension) public virtual onlyGovernance {
        _updateMaxDeadlineExtension(newMaxDeadlineExtension);
    }

    function updateBaseDeadlineExtension(uint256 newBaseDeadlineExtension) public virtual onlyGovernance {
        _updateBaseDeadlineExtension(newBaseDeadlineExtension);
    }

    function updateDecayPeriod(uint256 newDecayPeriod) public virtual onlyGovernance {
        _updateDecayPeriod(newDecayPeriod);
    }

    function updatePercentDecay(uint256 newPercentDecay) public virtual onlyGovernance {
        _updatePercentDecay(newPercentDecay);
    }

    function _updateMaxDeadlineExtension(uint256 newMaxDeadlineExtension) internal {
        if (
            newMaxDeadlineExtension > MAX_DEADLINE_EXTENSION
        ) revert MaxDeadlineExtensionTooLarge(MAX_DEADLINE_EXTENSION);

        emit MaxDeadlineExtensionSet(_maxDeadlineExtension, newMaxDeadlineExtension);
        // SafeCast unnecessary here as long as the MAX_BASE_DEADLINE_EXTENSION is less than type(uint64).max
        _maxDeadlineExtension = uint64(newMaxDeadlineExtension);
    }

    function _updateBaseDeadlineExtension(uint256 newBaseDeadlineExtension) internal {
        if (
            newBaseDeadlineExtension < MIN_BASE_DEADLINE_EXTENSION ||
            newBaseDeadlineExtension > MAX_BASE_DEADLINE_EXTENSION
        ) revert BaseDeadlineExtensionOutOfRange(MIN_BASE_DEADLINE_EXTENSION, MAX_BASE_DEADLINE_EXTENSION);

        emit BaseDeadlineExtensionSet(_baseDeadlineExtension, newBaseDeadlineExtension);
        // SafeCast unnecessary here as long as the MAX_BASE_DEADLINE_EXTENSION is less than type(uint64).max
        _baseDeadlineExtension = uint64(newBaseDeadlineExtension);
    }

    function _updateDecayPeriod(uint256 newDecayPeriod) internal {
        if (
            newDecayPeriod < MIN_DECAY_PERIOD ||
            newDecayPeriod > MAX_DECAY_PERIOD
        ) revert DecayPeriodOutOfRange(MIN_DECAY_PERIOD, MAX_DECAY_PERIOD);

        emit DecayPeriodSet(_decayPeriod, newDecayPeriod);
        // SafeCast unnecessary here as long as the MAX_DECAY_PERIOD is less than type(uint64).max
        _decayPeriod = uint64(newDecayPeriod);
    }

    function _updatePercentDecay(uint256 newPercentDecay) internal {
        if (
            newPercentDecay < MIN_PERCENT_DECAY ||
            newPercentDecay > MAX_PERCENT_DECAY
        ) revert PercentDecayOutOfRange(MIN_PERCENT_DECAY, MAX_PERCENT_DECAY);

        uint256 newInversePercentDecay = MAX_PERCENT_DECAY - newPercentDecay;
        emit PercentDecaySet(MAX_PERCENT_DECAY - _inversePercentDecay, newInversePercentDecay);
        // SafeCast unnecessary here as long as the MAX_PERCENT_DECAY is less than type(uint64).max
        _inversePercentDecay = uint64(newInversePercentDecay);
    }

    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal virtual override returns(uint256) {

        uint256 voteWeight = super._castVote(proposalId, account, support, reason, params);

        // Grab the max deadline extension
        uint256 maxDeadlineExtension_ = _maxDeadlineExtension;

        // If maxDeadlineExtension is set to zero, then no deadline updates needed, skip the rest to save gas
        if (maxDeadlineExtension_ == 0) {
            return voteWeight;
        }

        // Retrieve the existing deadline data for this proposal
        DeadlineData memory dd = _deadlineDatas[proposalId];

        // If extension is already maxxed out, no further updates needed
        if (dd.extendedBy >= maxDeadlineExtension_) return voteWeight;

        // If quorum wasn't reached last time, check again
        if (!dd.quorumReached) {
            dd.quorumReached = _quorumReached(proposalId);
            // If quorum still hasn't been reached, skip the calculation and return
            if (!dd.quorumReached) return voteWeight;
        }

        uint256 currentTimepoint = clock();

        // Initialize the rest of the struct if it hasn't been initialized yet
        if (dd.originalDeadline == 0) {
             // Assumes safe conversion, uint64 should be large enough for either block numbers or timestamps in seconds
            dd.originalDeadline = uint64(GovernorBase.proposalDeadline(proposalId));
            dd.currentDeadline = dd.originalDeadline;
        }

        // Initialize extendMultiple
        uint256 extendMultiple;

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
            uint256 baseDeadlineExtension_ = _baseDeadlineExtension;
            uint256 decayPeriod_ = _decayPeriod;
            uint256 inversePercentDecay_ = _inversePercentDecay;

            // Get the current distance from the deadline
            uint256 distanceFromDeadline = dd.currentDeadline - currentTimepoint;

            // We can return if we are outside the range of the base extension amount (since it gets subtracted out)
            if (baseDeadlineExtension_ < distanceFromDeadline) return voteWeight;

            // Extend amount decays past the original deadline
            if (currentTimepoint > dd.originalDeadline) {
                uint256 periodsElapsed = (currentTimepoint - dd.originalDeadline) / decayPeriod_;
                uint256 extend =
                    (baseDeadlineExtension_ * inversePercentDecay_**periodsElapsed) / (100**periodsElapsed);
                // Check again for distance from the deadline. If extend is too small, just return.
                if (extend < distanceFromDeadline) return voteWeight;
                extendMultiple = extend - distanceFromDeadline;
            } else {
                extendMultiple = baseDeadlineExtension_ - distanceFromDeadline;
            }

        }

        // We include a FRACTION_MULTIPLE that we later divide back out to circumvent integer division issues
        uint256 deadlineExtension = extendMultiple * Math.min(
            FRACTION_MULTIPLE_MAX,
            (
                voteWeight * FRACTION_MULTIPLE / ( _voteMargin(proposalId) + 1 ) // Add 1 to avoid divide by zero error
            )
        ) / FRACTION_MULTIPLE;

        // Only need to extend and emit if the extension is greater than 0
        if (deadlineExtension > 0) {

            // Update extended by with the extension value, maxing out at the max deadline extension
            dd.extendedBy += SafeCast.toUint64(Math.max(deadlineExtension, maxDeadlineExtension_));
            // Update the new deadline
            dd.currentDeadline = dd.originalDeadline + dd.extendedBy;

            // Set in storage
            _deadlineDatas[proposalId] = dd;

            // Emit the event
            emit ProposalExtended(proposalId, dd.currentDeadline);

        }

        return voteWeight;

    }
}