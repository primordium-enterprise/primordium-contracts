// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts v4.4.1 (extensions/GovernorSettings.sol)

pragma solidity ^0.8.20;

import {GovernorBase} from "./GovernorBase.sol";
import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";

/**
 * @dev Extension of {GovernorBase} for settings updatable through governance.
 *
 * By default, sets the proposal threshold in basis points, allowing the votes to fluctuate dynamically according to the
 * total allocated token supply. The maximum BPS to set the proposal threshold to is 1_000 (10%).
 *
 * _Available since v4.4._
 */
abstract contract GovernorSettings is GovernorBase {

    uint256 constant private MAX_BPS = 10_000;
    uint256 constant public MAX_PROPOSAL_THRESHOLD_BPS = 1_000;

    /// @notice The minimum setable voting delay, set to 1.
    uint256 public constant MIN_VOTING_DELAY = 1;
    /// @notice The maximum setable voting delay, set to approximately 1 week.
    uint256 public immutable MAX_VOTING_DELAY;

    /// @notice The minimum setable voting period, set to approximately 24 hours.
    uint256 public immutable MIN_VOTING_PERIOD;
    /// @notice The maximum setable voting period, set to approximately 2 weeks.
    uint256 public immutable MAX_VOTING_PERIOD;

    uint256 private _proposalThresholdBps;
    uint256 private _votingDelay;
    uint256 private _votingPeriod;

    event ProposalThresholdBpsSet(uint256 oldProposalThresholdBps, uint256 newProposalThresholdBps);
    event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);
    event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);

    error ProposalThresholdBpsTooLarge(uint256 max);
    error VotingDelayOutOfRange(uint256 min, uint256 max);
    error VotingPeriodOutOfRange(uint256 min, uint256 max);

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
     * @return threshold The total votes required.
     */
    function proposalThreshold() public view virtual override returns (uint256 threshold) {
        // Overflow not a problem as long as the token's max supply <= type(uint224).max
        IERC5805 _token = token();
        unchecked {
            threshold = (_token.getPastTotalSupply(_clock(_token) - 1) * _proposalThresholdBps) / MAX_BPS;
        }
    }

    /**
     * @dev Public function to see the current basis points value for the proposalThreshold.
     */
    function proposalThresholdBps() public view returns (uint256) {
        return _proposalThresholdBps;
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

    /**
     * @dev Update the proposal threshold BPS. This operation can only be performed through a governance proposal.
     *
     * Emits a {ProposalThresholdBpsSet} event.
     */
    function setProposalThresholdBps(uint256 newProposalThresholdBps) public virtual onlyGovernance {
        _setProposalThresholdBps(newProposalThresholdBps);
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
     * @dev Update the voting period. This operation can only be performed through a governance proposal.
     *
     * Emits a {VotingPeriodSet} event.
     */
    function setVotingPeriod(uint256 newVotingPeriod) public virtual onlyGovernance {
        _setVotingPeriod(newVotingPeriod);
    }

    /**
     * @dev Internal setter for the proposal threshold BPS.
     *
     * Emits a {ProposalThresholdBpsSet} event.
     */
    function _setProposalThresholdBps(uint256 newProposalThresholdBps) internal virtual {
        if (
            newProposalThresholdBps > MAX_PROPOSAL_THRESHOLD_BPS
        ) revert ProposalThresholdBpsTooLarge(MAX_PROPOSAL_THRESHOLD_BPS);

        emit ProposalThresholdBpsSet(_proposalThresholdBps, newProposalThresholdBps);
        _proposalThresholdBps = newProposalThresholdBps;
    }

    /**
     * @dev Internal setter for the voting delay.
     *
     * Emits a {VotingDelaySet} event.
     */
    function _setVotingDelay(uint256 newVotingDelay) internal virtual {
        if (
            newVotingDelay < MIN_VOTING_DELAY ||
            newVotingDelay > MAX_VOTING_DELAY
        ) revert VotingDelayOutOfRange(MIN_VOTING_DELAY, MAX_VOTING_DELAY);

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
        if (
            newVotingPeriod < MIN_VOTING_PERIOD ||
            newVotingPeriod > MAX_VOTING_PERIOD
        ) revert VotingPeriodOutOfRange(MIN_VOTING_PERIOD, MAX_VOTING_PERIOD);

        emit VotingPeriodSet(_votingPeriod, newVotingPeriod);
        _votingPeriod = newVotingPeriod;
    }

}
