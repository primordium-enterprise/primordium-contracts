// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {IGovernorBase} from "./IGovernorBase.sol";

interface IProposalDeadlineExtensions is IGovernorBase {
    struct ProposalDeadlineExtensionsInit {
        uint256 maxDeadlineExtension;
        uint256 baseDeadlineExtension;
        uint256 decayPeriod;
        uint256 percentDecay;
    }

    event ProposalDeadlineExtended(uint256 indexed proposalId, uint256 extendedDeadline);
    event MaxDeadlineExtensionUpdate(uint256 oldMaxDeadlineExtension, uint256 newMaxDeadlineExtension);
    event BaseDeadlineExtensionUpdate(uint256 oldBaseDeadlineExtension, uint256 newBaseDeadlineExtension);
    event ExtensionDecayPeriodUpdate(uint256 oldDecayPeriod, uint256 newDecayPeriod);
    event ExtensionPercentDecayUpdate(uint256 oldPercentDecay, uint256 newPercentDecay);

    error GovernorExtensionDecayPeriodCannotBeZero();
    error GovernorExtensionPercentDecayOutOfRange(uint256 min, uint256 max);

    /**
     * @inheritdoc IGovernorBase
     * @dev The proposal deadline can be dynamically extended on each vote according to the proposal deadline extension
     * parameters.
     */
    function proposalDeadline(uint256 proposalId) external view returns (uint256);

    /**
     * @notice The original proposal deadline before any extensions were applied.
     */
    function proposalOriginalDeadline(uint256 proposalId) external view returns (uint256);

    /**
     * @notice The maximum amount (according to the clock units) that a proposal can be extended.
     */
    function maxDeadlineExtension() external view returns (uint256);

    /**
     * @notice Governance-only function to update the max deadline extension. The DAO should set this parameter to
     * prevent a DoS attack where proposals are extended indefinitely.
     * @dev This should be set in the clock mode's units.
     */
    function setMaxDeadlineExtension(uint256 newMaxDeadlineExtension) external;

    /**
     * @notice The base extension period used in the deadline extension calculations. On each vote, if the vote occurs
     * close to the proposal deadline, the deadline is extended by a function of this amount.
     */
    function baseDeadlineExtension() external view returns (uint256);

    /**
     * @notice Governance-only function to update the base deadline extension.
     * @dev This should be set in the clock mode's units.
     */
    function setBaseDeadlineExtension(uint256 newBaseDeadlineExtension) external;

    /**
     * @notice The base deadline extension decays by {extensionPercentDecay} for every one of these periods past the
     * original proposal deadline that the current vote is occurring.
     */
    function extensionDecayPeriod() external view returns (uint256);

    /**
     * @notice Governance-only function to update the extension decay period.
     * @dev This should be set in the clock mode's units.
     */
    function setExtensionDecayPeriod(uint256 newDecayPeriod) external;

    /**
     * @notice The percentage amount that the base deadline extension decays by for every {extensionDecayPeriod} of time
     * past the original proposal deadline.
     * @dev This should be set in the clock mode's units.
     */
    function extensionPercentDecay() external view returns (uint256);

    /**
     * @notice Governance-only function to update the extension percent decay.
     * @dev This should be set in the clock mode's units.
     */
    function setExtensionPercentDecay(uint256 newPercentDecay) external;
}
