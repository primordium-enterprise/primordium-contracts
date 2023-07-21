// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "../Governor.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @dev A module to extend the deadline for controversial votes. The extension amount for each vote is dynamically
 * computed, taking several parameters into account, such as:
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
 * Through the governance process, the DAO can set the baseDeadlineExtension, the decayPeriod, and the percentDecay values.
 *
 */
abstract contract GovernorProposalDeadlineExtensions is Governor {

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
     * @notice The maximum decay period for additional deadline extensions, set to approximately 1 day.
     */
    uint256 public immutable MAX_DECAY_PERIOD;
    /**
     * @notice Maximum percent decay
     */
    uint256 public constant MAX_PERCENT_DECAY = 100;

    uint64 private _maxDeadlineExtension; // Setable by DAO, the max extension period for any given proposal
    event MaxDeadlineExtensionSet(uint256 oldMaxDeadlineExtension, uint256 newMaxDeadlineExtension);
    uint64 private _baseDeadlineExtension; // Setable by DAO, the base extension period for deadline extension calculations
    event BaseDeadlineExtensionSet(uint256 oldBaseDeadlineExtension, uint256 newBaseDeadlineExtension);
    uint64 private _decayPeriod; // Setable by DAO, base extension amount decays by {percentDecay()} every period
    event DecayPeriodSet(uint256 oldDecayPeriod, uint256 newDecayPeriod);
    uint64 private _inversePercentDecay; // Setable by DAO, store inverted (100% - percentDecay), saves a subtract op
    event PercentDecaySet(uint256 oldPercentDecay, uint256 newPercentDecay);

    struct DeadlineData {
        uint64 originalDeadline;
        uint64 extendedBy;
        uint64 currentDeadline;
        uint64 __gap_unused;
    }

    // Tracking the deadlines for a proposal
    mapping(uint256 => DeadlineData) private _deadlineDatas;

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
     * @notice The current max extension period for any given proposal. The voting period cannot be extended past the
     * original deadline more than this amount. DAOs can set this to zero for no extensions whatsoever.
     */
    function maxDeadlineExtension() public view returns (uint256) {
        return _maxDeadlineExtension;
    }

    function updateMaxDeadlineExtension(uint256 newMaxDeadlineExtension) public virtual onlyGovernance {
        _updateMaxDeadlineExtension(newMaxDeadlineExtension);
    }

    function _updateMaxDeadlineExtension(uint256 newMaxDeadlineExtension) internal {
        require(newMaxDeadlineExtension <= MAX_DEADLINE_EXTENSION, "maxDeadlineExtension too large");
        emit MaxDeadlineExtensionSet(_maxDeadlineExtension, newMaxDeadlineExtension);
        // SafeCast unnecessary here as long as the MAX_BASE_DEADLINE_EXTENSION is less than type(uint64).max
        _maxDeadlineExtension = uint64(newMaxDeadlineExtension);
    }

    /**
     * @notice The base extension period used in the deadline extension calculations. This amount by {percentDecay} for
     * every {decayPeriod} past the original proposal deadline.
     */
    function baseDeadlineExtension() public view virtual returns (uint256) {
        return _baseDeadlineExtension;
    }

    function updateBaseDeadlineExtension(uint256 newBaseDeadlineExtension) public virtual onlyGovernance {
        _updateBaseDeadlineExtension(newBaseDeadlineExtension);
    }

    function _updateBaseDeadlineExtension(uint256 newBaseDeadlineExtension) internal {
        require(
            newBaseDeadlineExtension >= MIN_BASE_DEADLINE_EXTENSION &&
            newBaseDeadlineExtension <= MAX_BASE_DEADLINE_EXTENSION, "baseDeadlineExtension out of range");
        emit BaseDeadlineExtensionSet(_baseDeadlineExtension, newBaseDeadlineExtension);
        // SafeCast unnecessary here as long as the MAX_BASE_DEADLINE_EXTENSION is less than type(uint64).max
        _baseDeadlineExtension = uint64(newBaseDeadlineExtension);
    }

    /**
     * @notice The base extension period decays by {percentDecay} for every period set by this parameter. DAOs should be
     * sure to set this period in accordance with their clock mode.
     */
    function decayPeriod() public view virtual returns (uint256) {
        return _decayPeriod;
    }

    function updateDecayPeriod(uint256 newDecayPeriod) public virtual onlyGovernance {
        _updateDecayPeriod(newDecayPeriod);
    }

    function _updateDecayPeriod(uint256 newDecayPeriod) internal {
        require(newDecayPeriod <= MAX_DECAY_PERIOD, "decayPeriod too large");
        emit DecayPeriodSet(_decayPeriod, newDecayPeriod);
        // SafeCast unnecessary here as long as the MAX_DECAY_PERIOD is less than type(uint64).max
        _decayPeriod = uint64(newDecayPeriod);
    }

    /**
     * @notice The percentage that the base extension period decays by for every {decayPeriod}.
     */
    function percentDecay() public view virtual returns (uint256) {
        return MAX_PERCENT_DECAY - _inversePercentDecay;
    }

    function updatePercentDecay(uint256 newPercentDecay) public virtual onlyGovernance {
        _updatePercentDecay(newPercentDecay);
    }

    function _updatePercentDecay(uint256 newPercentDecay) internal {
        require(newPercentDecay <= MAX_PERCENT_DECAY, "percentDecay must be no greater than 100%");
        uint256 newInversePercentDecay = MAX_PERCENT_DECAY - newPercentDecay;
        emit PercentDecaySet(MAX_PERCENT_DECAY - _inversePercentDecay, newInversePercentDecay);
        // SafeCast unnecessary here as long as the MAX_PERCENT_DECAY is less than type(uint64).max
        _inversePercentDecay = uint64(newInversePercentDecay);
    }

    function proposalDeadline(uint256 proposalId) public view virtual override returns (uint256) {
        uint256 currentDeadline = _deadlineDatas[proposalId].currentDeadline;
        // If uninitialized (no votes cast yet), return the original proposal deadline
        if (currentDeadline == 0) {
            return super.proposalDeadline(proposalId);
        }
        return currentDeadline;
    }

    function proposalDeadlineExtension(uint256 proposalId) public view virtual returns (uint256) {
        return _deadlineDatas[proposalId].currentDeadline;
    }

    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal virtual override returns(uint256) {

        uint256 weight = super._castVote(proposalId, account, support, reason, params);

        // Grab all four values from the slot at once to minimize storage reads
        uint256 maxDeadlineExtension_ = _maxDeadlineExtension;
        uint256 baseDeadlineExtension_ = _baseDeadlineExtension;
        uint256 decayPeriod_ = _decayPeriod;
        uint256 inversePercentDecay_ = _inversePercentDecay;

        // If maxDeadlineExtension is set to zero, then no deadline updates needed, skip to save gas
        if (maxDeadlineExtension_ == 0) {
            return weight;
        }

        // Retrieve the existing deadline data
        DeadlineData memory deadlineData = _deadlineDatas[proposalId];

        // If extension is already maxxed out, no further updates needed
        if (deadlineData.extendedBy >= maxDeadlineExtension_) {
            return weight;
        }

        // CHECK IF

        return weight;

    }
}