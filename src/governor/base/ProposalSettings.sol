// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts v4.4.1 (extensions/GovernorSettings.sol)

pragma solidity ^0.8.20;

import {GovernorBase} from "./GovernorBase.sol";
import {IGovernorBase} from "../interfaces/IGovernorBase.sol";
import {IGovernorToken} from "../interfaces/IGovernorToken.sol";
import {BasisPoints} from "src/libraries/BasisPoints.sol";
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

    /// @custom:storage-location erc7201:ProposalSettings.Storage
    struct ProposalSettingsStorage {
        uint16 _proposalThresholdBps;
        // uint24 allows each period to be up to 194 days long using timestamps (longer using block numbers)
        uint24 _votingDelay;
        uint24 _votingPeriod;
        // Grace period can be set to max to be unlimited
        uint48 _gracePeriod;
    }

    // keccak256(abi.encode(uint256(keccak256("ProposalSettings.Storage")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant PROPOSAL_BASE_STORAGE = 0x886170c74db156f102a26882ea120c8a2a8352444c7ba2b962b9c75d7a2ed900;

    function _getProposalSettingsStorage() private pure returns (ProposalSettingsStorage storage $) {
        assembly {
            $.slot := PROPOSAL_BASE_STORAGE
        }
    }

    event ProposalThresholdBpsSet(uint256 oldProposalThresholdBps, uint256 newProposalThresholdBps);
    event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);
    event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);
    event ProposalGracePeriodSet(uint256 oldGracePeriod, uint256 newGracePeriod);

    function __ProposalSettings_init(
        uint256 proposalThresholdBps_,
        uint256 votingDelay_,
        uint256 votingPeriod_,
        uint256 gracePeriod_
    )
        internal
        virtual
        onlyInitializing
    {
        _setProposalThresholdBps(proposalThresholdBps_);
        _setVotingDelay(votingDelay_);
        _setVotingPeriod(votingPeriod_);
        _setProposalGracePeriod(gracePeriod_);
    }

    /// @inheritdoc IGovernorBase
    function proposalThreshold() public view virtual override returns (uint256 votesThreshold) {
        // Overflow not a problem as long as the token's max supply <= type(uint224).max
        IGovernorToken _token = token();
        votesThreshold = uint256(_getProposalSettingsStorage()._proposalThresholdBps).bpsUnchecked(
            _token.getPastTotalSupply(_clock(_token)) - 1
        );
    }

    /**
     * @dev Public function to see the current basis points value for the proposalThreshold.
     */
    function proposalThresholdBps() public view returns (uint256 _proposalThresholdBps) {
        _proposalThresholdBps = _getProposalSettingsStorage()._proposalThresholdBps;
    }

    /**
     * @dev Update the proposal threshold BPS.
     * @notice This operation can only be performed through a governance proposal.
     * Emits a {ProposalThresholdBpsSet} event.
     */
    function setProposalThresholdBps(uint256 newProposalThresholdBps) public virtual onlyGovernance {
        _setProposalThresholdBps(newProposalThresholdBps);
    }

    function _setProposalThresholdBps(uint256 newProposalThresholdBps) internal virtual {
        ProposalSettingsStorage storage $ = _getProposalSettingsStorage();
        emit ProposalThresholdBpsSet($._proposalThresholdBps, newProposalThresholdBps);
        $._proposalThresholdBps = SafeCast.toUint16(newProposalThresholdBps);
    }

    /// @inheritdoc IGovernorBase
    function votingDelay() public view virtual override returns (uint256 _votingDelay) {
        _votingDelay = _getProposalSettingsStorage()._votingDelay;
    }

    /**
     * @dev Update the voting delay.
     * @notice This operation can only be performed through a governance proposal.
     * Emits a {VotingDelaySet} event.
     */
    function setVotingDelay(uint256 newVotingDelay) public virtual onlyGovernance {
        _setVotingDelay(newVotingDelay);
    }

    function _setVotingDelay(uint256 newVotingDelay) internal virtual {
        ProposalSettingsStorage storage $ = _getProposalSettingsStorage();
        emit VotingDelaySet($._votingDelay, newVotingDelay);
        $._votingDelay = SafeCast.toUint24(newVotingDelay);
    }

    /// @inheritdoc IGovernorBase
    function votingPeriod() public view virtual override returns (uint256 _votingPeriod) {
        _votingPeriod = _getProposalSettingsStorage()._votingPeriod;
    }

    /**
     * @dev Update the voting period.
     * @notice This operation can only be performed through a governance proposal.
     * Emits a {VotingPeriodSet} event.
     */
    function setVotingPeriod(uint256 newVotingPeriod) public virtual onlyGovernance {
        _setVotingPeriod(newVotingPeriod);
    }

    function _setVotingPeriod(uint256 newVotingPeriod) internal virtual {
        ProposalSettingsStorage storage $ = _getProposalSettingsStorage();
        emit VotingPeriodSet($._votingPeriod, newVotingPeriod);
        $._votingPeriod = SafeCast.toUint24(newVotingPeriod);
    }

    function _getVotingDelayAndPeriod()
        internal
        view
        virtual
        override
        returns (uint256 _votingDelay, uint256 _votingPeriod)
    {
        ProposalSettingsStorage storage $ = _getProposalSettingsStorage();
        _votingDelay = $._votingDelay;
        _votingPeriod = $._votingPeriod;
    }

    /// @inheritdoc IGovernorBase
    function proposalGracePeriod() public view virtual override returns (uint256 _gracePeriod) {
        _gracePeriod = _getProposalSettingsStorage()._gracePeriod;
    }

    /**
     * @dev Update the proposal grace period.
     * @notice This operation can only be performed through a governance proposal.
     * Emits a {ProposalGracePeriodSet} event.
     */
    function setProposalGracePeriod(uint256 newGracePeriod) public virtual onlyGovernance {
        _setProposalGracePeriod(newGracePeriod);
    }

    function _setProposalGracePeriod(uint256 newGracePeriod) internal virtual {
        // Don't allow overflow for setting to a high value "unlimited" value
        if (newGracePeriod > type(uint48).max) {
            newGracePeriod = type(uint48).max;
        }

        ProposalSettingsStorage storage $ = _getProposalSettingsStorage();
        emit ProposalGracePeriodSet($._gracePeriod, newGracePeriod);
        $._gracePeriod = uint48(newGracePeriod);
    }
}
