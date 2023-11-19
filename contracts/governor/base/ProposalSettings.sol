// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts v4.4.1 (extensions/GovernorSettings.sol)

pragma solidity ^0.8.20;

import {GovernorBase} from "./GovernorBase.sol";
import {IGovernorToken} from "../interfaces/IGovernorToken.sol";
import {BasisPoints} from "contracts/libraries/BasisPoints.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title ProposalSettings
 *
 * @dev Extends {GovernorBase} with updateable proposal settings, such as the proposalThreshold in basis points, the
 * proposal voting delay, and the proposal voting period.
 *
 * By default, the maximum proposal threshold is 10% (1_000 bps). This can be overridden.
 *
 * @author Ben Jett - @BCJdevelopment
 */
abstract contract ProposalSettings is GovernorBase {
    using BasisPoints for uint256;

    /// @notice The minimum setable voting delay, set to 1 (regardless of clock mode)
    uint256 public constant MIN_VOTING_DELAY = 1;
    /// @notice The maximum setable voting delay, set to approximately 1 week at 12sec/block.
    uint256 private constant MAX_VOTING_DELAY_BLOCKS = 50_400;
    /// @notice The minimum setable voting period, set to approximately 24 hours at 12sec/block.
    uint256 private constant MIN_VOTING_PERIOD_BLOCKS = 7_200;
    /// @notice The maximum setable voting period, set to approximately 2 weeks at 12sec/block.
    uint256 private constant MAX_VOTING_PERIOD_BLOCKS = 100_800;

    /// @dev The seconds per block, set in the constructor based on the chain used.
    uint256 private immutable SECONDS_PER_BLOCK;

    /// @custom:storage-location erc7201:ProposalSettings.Storage
    struct ProposalSettingsStorage {
        uint16 _proposalThresholdBps;
        // uint24 allows each period to be up to 194 days long using seconds for the clock (longer using block numbers)
        uint24 _votingDelay;
        uint24 _votingPeriod;
    }

    bytes32 private immutable PROPOSAL_BASE_STORAGE =
        keccak256(abi.encode(uint256(keccak256("ProposalSettings.Storage")) - 1)) & ~bytes32(uint256(0xff));

    function _getProposalSettingsStorage() private view returns (ProposalSettingsStorage storage $) {
        bytes32 governorBaseStorageSlot = PROPOSAL_BASE_STORAGE;
        assembly {
            $.slot := governorBaseStorageSlot
        }
    }

    event ProposalThresholdBpsSet(uint256 oldProposalThresholdBps, uint256 newProposalThresholdBps);
    event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);
    event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);

    error ProposalThresholdBpsTooLarge(uint256 providedBps, uint256 maxBps);
    error VotingDelayOutOfRange(uint256 min, uint256 max);
    error VotingPeriodOutOfRange(uint256 min, uint256 max);

    constructor(uint256 secondsPerBlock) {
        SECONDS_PER_BLOCK = secondsPerBlock > 0 ? secondsPerBlock : 12; // assumes 12 seconds per block
    }

    function __ProposalSettings_init(
        uint256 proposalThresholdBps_,
        uint256 votingDelay_,
        uint256 votingPeriod_
    ) internal virtual {
        _setProposalThresholdBps(proposalThresholdBps_);
        _setVotingDelay(votingDelay_);
        _setVotingPeriod(votingPeriod_);
    }

    function MAX_PROPOSAL_THRESHOLD_BPS() public virtual returns (uint256 maxProposalThresholdBps) {
        maxProposalThresholdBps = 1_000;
    }

    function MAX_VOTING_DELAY() public view virtual returns (uint256 maxVotingDelay) {
        maxVotingDelay = _convertBlockPeriodByClock(MAX_VOTING_DELAY_BLOCKS);
    }

    function MIN_VOTING_PERIOD() public view virtual returns (uint256 minVotingPeriod) {
        minVotingPeriod = _convertBlockPeriodByClock(MIN_VOTING_PERIOD_BLOCKS);
    }

    function MAX_VOTING_PERIOD() public view virtual returns (uint256 maxVotingPeriod) {
        maxVotingPeriod = _convertBlockPeriodByClock(MAX_VOTING_PERIOD_BLOCKS);
    }

    /**
     * @dev Returns the current proposal threshold of votes required to submit a proposal, as a basis points function of
     * the current total supply.
     * @return votesThreshold The total votes required.
     */
    function proposalThreshold() public view virtual override returns (uint256 votesThreshold) {
        // Overflow not a problem as long as the token's max supply <= type(uint224).max
        IGovernorToken _token = token();
        votesThreshold = uint256(_getProposalSettingsStorage()._proposalThresholdBps)
            .bpsUnchecked(_token.getPastTotalSupply(_clock(_token)) - 1);
    }

    /**
     * @dev Public function to see the current basis points value for the proposalThreshold.
     */
    function proposalThresholdBps() public view returns (uint256 _proposalThresholdBps) {
        _proposalThresholdBps = _getProposalSettingsStorage()._proposalThresholdBps;
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
        uint256 maxProposalThresholdBps = MAX_PROPOSAL_THRESHOLD_BPS();
        if (
            newProposalThresholdBps > maxProposalThresholdBps
        ) revert ProposalThresholdBpsTooLarge(newProposalThresholdBps, maxProposalThresholdBps);

        ProposalSettingsStorage storage $ = _getProposalSettingsStorage();
        emit ProposalThresholdBpsSet($._proposalThresholdBps, newProposalThresholdBps);
        $._proposalThresholdBps = SafeCast.toUint16(newProposalThresholdBps);
    }

    /**
     * @dev See {IGovernor-votingDelay}.
     */
    function votingDelay() public view virtual override returns (uint256 _votingDelay) {
        _votingDelay = _getProposalSettingsStorage()._votingDelay;
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
        uint256 maxVotingDelay = MAX_VOTING_DELAY();
        if (
            newVotingDelay < MIN_VOTING_DELAY ||
            newVotingDelay > maxVotingDelay
        ) revert VotingDelayOutOfRange(MIN_VOTING_DELAY, maxVotingDelay);

        ProposalSettingsStorage storage $ = _getProposalSettingsStorage();
        emit VotingDelaySet($._votingDelay, newVotingDelay);
        $._votingDelay = SafeCast.toUint24(newVotingDelay);
    }

    /**
     * @dev See {IGovernor-votingPeriod}.
     */
    function votingPeriod() public view virtual override returns (uint256 _votingPeriod) {
        _votingPeriod =  _getProposalSettingsStorage()._votingPeriod;
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
        bool usesBlockNumbers = clock() == block.number;
        uint256 minVotingPeriod = _convertBlockPeriod(MIN_VOTING_PERIOD_BLOCKS, usesBlockNumbers);
        uint256 maxVotingPeriod = _convertBlockPeriod(MAX_VOTING_PERIOD_BLOCKS, usesBlockNumbers);
        // voting period must be at least one block long
        if (
            newVotingPeriod < minVotingPeriod ||
            newVotingPeriod > maxVotingPeriod
        ) revert VotingPeriodOutOfRange(minVotingPeriod, maxVotingPeriod);

        ProposalSettingsStorage storage $ = _getProposalSettingsStorage();
        emit VotingPeriodSet($._votingPeriod, newVotingPeriod);
        $._votingPeriod = SafeCast.toUint24(newVotingPeriod);
    }

    function _getVotingDelayAndPeriod() internal view virtual override returns (
        uint256 _votingDelay,
        uint256 _votingPeriod
    ) {
        ProposalSettingsStorage storage $ = _getProposalSettingsStorage();
        _votingDelay = $._votingDelay;
        _votingPeriod = $._votingPeriod;
    }

    function _convertBlockPeriodByClock(uint256 period) private view returns (uint256 converted) {
        converted = _convertBlockPeriod(period, clock() == block.number);
    }

    function _convertBlockPeriod(uint256 period, bool usesBlockNumbers) private view returns (uint256 converted) {
        converted = usesBlockNumbers ? period : period * SECONDS_PER_BLOCK;
    }
}
