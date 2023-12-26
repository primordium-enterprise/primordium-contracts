// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {ProposalsLogicV1} from "./logic/ProposalsLogicV1.sol";
import {ProposalVotingLogicV1} from "./logic/ProposalVotingLogicV1.sol";
import {ProposalDeadlineExtensionsLogicV1} from "./logic/ProposalDeadlineExtensionsLogicV1.sol";
import {ProposalVoting} from "./ProposalVoting.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title ProposalDeadlineExtensions
 * @author Ben Jett - @BCJdevelopment
 * @notice A module to extend the deadline for controversial votes. The extension amount for each vote is dynamically
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
 */
abstract contract ProposalDeadlineExtensions is ProposalVoting {

    function __ProposalDeadlineExtensions_init_unchained(bytes memory proposalDeadlineExtensionsInitParams)
        internal
        virtual
        onlyInitializing
    {
        (uint256 maxDeadlineExtension_, uint256 baseDeadlineExtension_, uint256 decayPeriod_, uint256 percentDecay_) =
            abi.decode(proposalDeadlineExtensionsInitParams, (uint256, uint256, uint256, uint256));

        _setMaxDeadlineExtension(maxDeadlineExtension_);
        _setBaseDeadlineExtension(baseDeadlineExtension_);
        _setExtensionDecayPeriod(decayPeriod_);
        _setExtensionPercentDecay(percentDecay_);
    }

    /**
     * @dev We override to provide the extended deadline (if applicable)
     */
    function proposalDeadline(uint256 proposalId) public view virtual override returns (uint256) {
        return ProposalDeadlineExtensionsLogicV1._proposalDeadline(proposalId);
    }

    function proposalOriginalDeadline(uint256 proposalId) public view virtual returns (uint256) {
        return ProposalDeadlineExtensionsLogicV1._originalProposalDeadline(proposalId);
    }

    /**
     * @notice The current max extension period for any given proposal. The voting period cannot be extended past the
     * original deadline more than this amount. DAOs can set this to zero for no extensions whatsoever.
     */
    function maxDeadlineExtension() public view virtual returns (uint256) {
        return ProposalDeadlineExtensionsLogicV1._maxDeadlineExtension();
    }

    function setMaxDeadlineExtension(uint256 newMaxDeadlineExtension) public virtual onlyGovernance {
        _setMaxDeadlineExtension(newMaxDeadlineExtension);
    }

    function _setMaxDeadlineExtension(uint256 newMaxDeadlineExtension) internal virtual {
        ProposalDeadlineExtensionsLogicV1.setMaxDeadlineExtension(newMaxDeadlineExtension);
    }

    /**
     * @notice The base extension period used in the deadline extension calculations. This amount by {percentDecay} for
     * every {decayPeriod} past the original proposal deadline.
     */
    function baseDeadlineExtension() public view virtual returns (uint256) {
        return ProposalDeadlineExtensionsLogicV1._baseDeadlineExtension();
    }

    function setBaseDeadlineExtension(uint256 newBaseDeadlineExtension) public virtual onlyGovernance {
        _setBaseDeadlineExtension(newBaseDeadlineExtension);
    }

    function _setBaseDeadlineExtension(uint256 newBaseDeadlineExtension) internal virtual {
        ProposalDeadlineExtensionsLogicV1.setBaseDeadlineExtension(newBaseDeadlineExtension);
    }

    /**
     * @notice The base extension period decays by {percentDecay} for every period set by this parameter. DAOs should be
     * sure to set this period in accordance with their clock mode.
     */
    function extensionDecayPeriod() public view virtual returns (uint256) {
        return ProposalDeadlineExtensionsLogicV1._extensionDecayPeriod();
    }

    function setExtensionDecayPeriod(uint256 newDecayPeriod) public virtual onlyGovernance {
        _setExtensionDecayPeriod(newDecayPeriod);
    }

    function _setExtensionDecayPeriod(uint256 newDecayPeriod) internal virtual {
        return ProposalDeadlineExtensionsLogicV1.setExtensionDecayPeriod(newDecayPeriod);
    }

    /**
     * @notice The percentage that the base extension period decays by for every {decayPeriod}.
     */
    function extensionPercentDecay() public view virtual returns (uint256) {
        return ProposalDeadlineExtensionsLogicV1._extensionDecayPeriod();
    }

    function setExtensionPercentDecay(uint256 newPercentDecay) public virtual onlyGovernance {
        _setExtensionPercentDecay(newPercentDecay);
    }

    function _setExtensionPercentDecay(uint256 newPercentDecay) internal virtual {
        ProposalDeadlineExtensionsLogicV1.setExtensionPercentDecay(newPercentDecay);
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
        returns (uint256 voteWeight)
    {
        voteWeight = super._castVote(proposalId, account, support, reason, params);
        ProposalDeadlineExtensionsLogicV1.processDeadlineExtensionOnVote(proposalId, voteWeight);
    }
}
