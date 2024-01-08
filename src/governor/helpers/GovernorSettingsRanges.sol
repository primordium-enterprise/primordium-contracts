// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {GovernorBase} from "../base/GovernorBase.sol";
import {Proposals} from "../base/Proposals.sol";
import {ProposalDeadlineExtensions} from "../base/ProposalDeadlineExtensions.sol";

abstract contract GovernorSettingsRanges is ProposalDeadlineExtensions {
    /**
     * Proposals.sol
     */

    error GovernorVotingDelayOutOfRange(uint256 min, uint256 max);
    error GovernorVotingPeriodOutOfRange(uint256 min, uint256 max);
    error GovernorProposalGracePeriodOutOfRange(uint256 min, uint256 max);

    /// @notice The minimum setable voting delay
    uint256 public immutable MIN_VOTING_DELAY = 1;

    /// @notice The maximum setable voting delay
    uint256 public immutable MAX_VOTING_DELAY = 1 weeks / 12;

    /// @notice The minimum setable voting period
    uint256 public immutable MIN_VOTING_PERIOD = 1 days / 12;

    /// @notice The maximum setable voting period
    uint256 public immutable MAX_VOTING_PERIOD = 2 weeks / 12;

    /// @notice The minimum setable proposal grace period
    uint256 public immutable MIN_PROPOSAL_GRACE_PERIOD = 2 weeks / 12;

    /// @notice The maximum setable proposal grace period
    uint256 public immutable MAX_PROPOSAL_GRACE_PERIOD = 12 weeks / 12;

    function _setVotingDelay(uint256 newVotingDelay) internal virtual override {
        if (newVotingDelay < MIN_VOTING_DELAY || newVotingDelay > MAX_VOTING_DELAY) {
            revert GovernorVotingDelayOutOfRange(MIN_VOTING_DELAY, MAX_VOTING_DELAY);
        }
        super._setVotingDelay(newVotingDelay);
    }

    function _setVotingPeriod(uint256 newVotingPeriod) internal virtual override {
        if (newVotingPeriod < MIN_VOTING_PERIOD || newVotingPeriod > MAX_VOTING_PERIOD) {
            revert GovernorVotingPeriodOutOfRange(MIN_VOTING_PERIOD, MAX_VOTING_PERIOD);
        }
        super._setVotingPeriod(newVotingPeriod);
    }

    function _setProposalGracePeriod(uint256 newGracePeriod) internal virtual override {
        if (newGracePeriod < MIN_PROPOSAL_GRACE_PERIOD || newGracePeriod > MAX_PROPOSAL_GRACE_PERIOD) {
            revert GovernorProposalGracePeriodOutOfRange(MIN_PROPOSAL_GRACE_PERIOD, MAX_PROPOSAL_GRACE_PERIOD);
        }
        super._setProposalGracePeriod(newGracePeriod);
    }

    /**
     * ProposalDeadlineExtensions.sol
     */

    error GovernorMaxDeadlineExtensionTooLarge(uint256 max);
    error GovernorBaseDeadlineExtensionOutOfRange(uint256 min, uint256 max);
    error GovernorExtensionDecayPeriodOutOfRange(uint256 min, uint256 max);

    /// @notice The absolute max amount that the deadline can be extended by
    uint256 public immutable ABSOLUTE_MAX_DEADLINE_EXTENSION = 2 weeks / 12;

    /// @notice The minimum base extension period for extending votes
    uint256 public immutable MIN_BASE_DEADLINE_EXTENSION = 6 hours / 12;

    /// @notice The maximum base extension period for extending votes
    uint256 public immutable MAX_BASE_DEADLINE_EXTENSION = 3 days / 12;

    /// @notice The decay period must be greater than zero, so the minimum is 1.
    uint256 public immutable MIN_EXTENSION_DECAY_PERIOD = 1;

    /// @notice The maximum decay period for additional deadline extensions, set to approximately 1 day.
    uint256 public immutable MAX_EXTENSION_DECAY_PERIOD = 1 days / 12;

    function _setMaxDeadlineExtension(uint256 newMaxDeadlineExtension) internal virtual override {
        if (newMaxDeadlineExtension > ABSOLUTE_MAX_DEADLINE_EXTENSION) {
            revert GovernorMaxDeadlineExtensionTooLarge(ABSOLUTE_MAX_DEADLINE_EXTENSION);
        }
        super._setMaxDeadlineExtension(newMaxDeadlineExtension);
    }

    function _setBaseDeadlineExtension(uint256 newBaseDeadlineExtension) internal virtual override {
        // forgefmt: disable-next-item
        if (
            newBaseDeadlineExtension < MIN_BASE_DEADLINE_EXTENSION ||
            newBaseDeadlineExtension > MAX_BASE_DEADLINE_EXTENSION
        ) {
            revert GovernorBaseDeadlineExtensionOutOfRange(MIN_BASE_DEADLINE_EXTENSION, MAX_BASE_DEADLINE_EXTENSION);
        }
        super._setBaseDeadlineExtension(newBaseDeadlineExtension);
    }

    function _setExtensionDecayPeriod(uint256 newDecayPeriod) internal virtual override {
        if (newDecayPeriod < MIN_EXTENSION_DECAY_PERIOD || newDecayPeriod > MAX_EXTENSION_DECAY_PERIOD) {
            revert GovernorExtensionDecayPeriodOutOfRange(MIN_EXTENSION_DECAY_PERIOD, MAX_EXTENSION_DECAY_PERIOD);
        }
        super._setExtensionDecayPeriod(newDecayPeriod);
    }
}
