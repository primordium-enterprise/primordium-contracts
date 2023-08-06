// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts v4.4.1 (governance/extensions/GovernorSettings.sol)

pragma solidity ^0.8.0;

import "../Governor.sol";

/**
 * @dev Extension of {Governor} for settings updatable through governance.
 *
 * By default, sets the proposal threshold in basis points, allowing the votes to fluctuate dynamically according to the
 * total allocated token supply. The maximum BPS to set the proposal threshold to is 1_000 (10%).
 *
 * _Available since v4.4._
 */
abstract contract GovernorSettings is Governor {

    uint256 constant private MAX_BPS = 10_000;
    uint256 constant public MAX_PROPOSAL_THRESHOLD_BPS = 1_000;

    uint256 private _proposalThresholdBps;
    event ProposalThresholdBpsSet(uint256 oldProposalThresholdBps, uint256 newProposalThresholdBps);

    uint256 private _votingDelay;
    /// @notice The minimum setable voting delay, set to 1.
    uint256 public constant MIN_VOTING_DELAY = 1;
    /// @notice The maximum setable voting delay, set to approximately 1 week.
    uint256 public immutable MAX_VOTING_DELAY;
    event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);

    uint256 private _votingPeriod;
    /// @notice The minimum setable voting period, set to approximately 24 hours.
    uint256 public immutable MIN_VOTING_PERIOD;
    /// @notice The maximum setable voting period, set to approximately 2 weeks.
    uint256 public immutable MAX_VOTING_PERIOD;
    event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);

    /**
     * @dev Initialize the governance parameters.
     */
    constructor(
        uint256 proposalThresholdBps_,
        uint256 votingDelay_,
        uint256 votingPeriod_
    ) {
        _setProposalThresholdBps(proposalThresholdBps_);

        // Initialize immutables based on clock (assumes seconds if not block number)
        bool usesBlockNumber = clock() == block.number;
        MAX_VOTING_DELAY = usesBlockNumber ?
            50_400 : // About 1 week at 12sec/block
            1 weeks;
        MIN_VOTING_PERIOD = usesBlockNumber ?
            7_200 : // About 24 hours at 12sec/block
            1 days;
        MAX_VOTING_PERIOD = usesBlockNumber ?
            100_800 : // About 2 weeks at 12sec/block
            2 weeks;

        _setVotingDelay(votingDelay_);
        _setVotingPeriod(votingPeriod_);
    }

    /**
     * @dev Returns the current proposal threshold of votes required to submit a proposal, as a basis points function of
     * the current total supply.
     */
    function proposalThreshold() public view virtual override returns (uint256) {
        // Overflow not a problem as long as the token's max supply <= type(uint224).max
        return (_token.totalSupply() * _proposalThresholdBps) / MAX_BPS;
    }

    /**
     * @dev Public function to see the current basis points value for the proposalThreshold.
     */
    function proposalThresholdBps() public view returns (uint256) {
        return _proposalThresholdBps;
    }

    /**
     * @dev Update the proposal threshold BPS. This operation can only be performed through a governance proposal.
     *
     * Emits a {ProposalThresholdBpsSet} event.
     */
    function setProposalThresholdBps(uint256 newProposalThresholdBps) public virtual onlyGovernance {
        _setProposalThresholdBps(newProposalThresholdBps);
    }

    /**
     * @dev Internal setter for the proposal threshold BPS.
     *
     * Emits a {ProposalThresholdBpsSet} event.
     */
    function _setProposalThresholdBps(uint256 newProposalThresholdBps) internal virtual {
        require(newProposalThresholdBps <= MAX_PROPOSAL_THRESHOLD_BPS);
        emit ProposalThresholdBpsSet(_proposalThresholdBps, newProposalThresholdBps);
        _proposalThresholdBps = newProposalThresholdBps;
    }

    /**
     * @dev See {IGovernor-votingDelay}.
     */
    function votingDelay() public view virtual override returns (uint256) {
        return _votingDelay;
    }

    /**
     * @dev Update the voting delay. This operation can only be performed through a governance proposal.
     *
     * Emits a {VotingDelaySet} event.
     */
    function setVotingDelay(uint256 newVotingDelay) public virtual onlyGovernance {
        _setVotingDelay(newVotingDelay);
    }

    /**
     * @dev Internal setter for the voting delay.
     *
     * Emits a {VotingDelaySet} event.
     */
    function _setVotingDelay(uint256 newVotingDelay) internal virtual {
        require(
            newVotingDelay >= MIN_VOTING_DELAY && newVotingDelay <= MAX_VOTING_DELAY,
            "GovernorSettings: Invalid voting delay"
        );
        emit VotingDelaySet(_votingDelay, newVotingDelay);
        _votingDelay = newVotingDelay;
    }

    /**
     * @dev See {IGovernor-votingPeriod}.
     */
    function votingPeriod() public view virtual override returns (uint256) {
        return _votingPeriod;
    }

    /**
     * @dev Update the voting period. This operation can only be performed through a governance proposal.
     *
     * Emits a {VotingPeriodSet} event.
     */
    function setVotingPeriod(uint256 newVotingPeriod) public virtual onlyGovernance {
        _setVotingPeriod(newVotingPeriod);
    }

    /**
     * @dev Internal setter for the voting period.
     *
     * Emits a {VotingPeriodSet} event.
     */
    function _setVotingPeriod(uint256 newVotingPeriod) internal virtual {
        // voting period must be at least one block long
        require(
            newVotingPeriod >= MIN_VOTING_PERIOD && newVotingPeriod <= MAX_VOTING_PERIOD,
            "GovernorSettings: voting period too low"
        );
        emit VotingPeriodSet(_votingPeriod, newVotingPeriod);
        _votingPeriod = newVotingPeriod;
    }

}
