// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts v4.4.1 (governance/extensions/GovernorSettings.sol)

pragma solidity ^0.8.0;

import "../Governor.sol";

/**
 * @dev Extension of {Governor} for settings updatable through governance.
 *
 * _Available since v4.4._
 */
abstract contract GovernorSettings is Governor {

    uint256 private _proposalThreshold;
    event ProposalThresholdSet(uint256 oldProposalThreshold, uint256 newProposalThreshold);

    uint256 private _votingDelay;
    /// @notice The minimum setable voting delay
    uint256 public constant MIN_VOTING_DELAY = 1;
    /// @notice The maximum setable voting delay, set to approximately 1 week
    uint256 public immutable MAX_VOTING_DELAY;
    event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);

    uint256 private _votingPeriod;
    /// @notice The minimum setable voting period, set to approximately 24 hours
    uint256 public immutable MIN_VOTING_PERIOD;
    /// @notice The maximum setable voting period, set to approximately 2 weeks
    uint256 public immutable MAX_VOTING_PERIOD;
    event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);

    /**
     * @dev Initialize the governance parameters.
     */
    constructor(uint256 initialVotingDelay, uint256 initialVotingPeriod, uint256 initialProposalThreshold) {
        // Initialize immutables
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

        _setVotingDelay(initialVotingDelay);
        _setVotingPeriod(initialVotingPeriod);
        _setProposalThreshold(initialProposalThreshold);
    }

    /**
     * @dev See {IGovernor-votingDelay}.
     */
    function votingDelay() public view virtual override returns (uint256) {
        return _votingDelay;
    }

    /**
     * @dev See {IGovernor-votingPeriod}.
     */
    function votingPeriod() public view virtual override returns (uint256) {
        return _votingPeriod;
    }

    // /**
    //  * @dev See {Governor-proposalThreshold}.
    //  */
    // function proposalThreshold() public view virtual override returns (uint256) {
    //     return _proposalThreshold;
    // }

    /**
     * @dev Update the voting delay. This operation can only be performed through a governance proposal.
     *
     * Emits a {VotingDelaySet} event.
     */
    function setVotingDelay(uint256 newVotingDelay) public virtual onlyGovernance {
        _setVotingDelay(newVotingDelay);
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
     * @dev Update the proposal threshold. This operation can only be performed through a governance proposal.
     *
     * Emits a {ProposalThresholdSet} event.
     */
    function setProposalThreshold(uint256 newProposalThreshold) public virtual onlyGovernance {
        _setProposalThreshold(newProposalThreshold);
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

    /**
     * @dev Internal setter for the proposal threshold.
     *
     * Emits a {ProposalThresholdSet} event.
     */
    function _setProposalThreshold(uint256 newProposalThreshold) internal virtual {
        emit ProposalThresholdSet(_proposalThreshold, newProposalThreshold);
        _proposalThreshold = newProposalThreshold;
    }

}
