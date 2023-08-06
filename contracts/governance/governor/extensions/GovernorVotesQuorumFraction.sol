// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts (last updated v4.8.0) (governance/extensions/GovernorVotesQuorumFraction.sol)

pragma solidity ^0.8.0;

import "./GovernorVotes.sol";
import "@openzeppelin/contracts/utils/Checkpoints.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @dev Extension of {Governor} for voting weight extraction from an {ERC20Votes} token and a quorum expressed as a
 * fraction of the total supply.
 *
 * The DAO can set the {quorumNumerator} to zero to allow any vote to pass without a quorum.
 *
 * _Available since v4.3._
 */
abstract contract GovernorVotesQuorumFraction is GovernorVotes {
    using SafeCast for *;
    using Checkpoints for Checkpoints.Trace224;

    Checkpoints.Trace224 private _quorumNumeratorCheckpoints;

    event QuorumNumeratorUpdated(uint256 oldQuorumNumerator, uint256 newQuorumNumerator);

    /**
     * @dev Initialize quorum as a fraction of the token's total supply.
     *
     * The fraction is specified as `numerator / denominator`. By default the denominator is 10_000, so quorum is
     * specified as a percent: a numerator of 1_000 corresponds to quorum being 10% of total supply. The denominator can
     * be customized by overriding {quorumDenominator}.
     */
    constructor(uint256 quorumNumerator_) {
        _updateQuorumNumerator(quorumNumerator_);
    }

    /**
     * @dev Returns the current quorum numerator. See {quorumDenominator}.
     */
    function quorumNumerator() public view virtual returns (uint256) {
        return _quorumNumeratorCheckpoints.latest();
    }

    /**
     * @dev Returns the quorum numerator at a specific timepoint. See {quorumDenominator}.
     */
    function quorumNumerator(uint256 timepoint) public view virtual returns (uint256) {
        // Optimistic search, check the latest checkpoint
        (bool exists, uint256 _key, uint256 _value) = _quorumNumeratorCheckpoints.latestCheckpoint();
        if (exists && _key <= timepoint) {
            return _value;
        }

        // Otherwise, do the binary search
        return _quorumNumeratorCheckpoints.upperLookupRecent(timepoint.toUint32());
    }

    /**
     * @dev Returns the quorum denominator. Defaults to 10_000, but may be overridden.
     */
    function quorumDenominator() public view virtual returns (uint256) {
        return 10_000;
    }

    /**
     * @dev Returns the quorum for a timepoint, in terms of number of votes: `supply * numerator / denominator`.
     */
    function quorum(uint256 timepoint) public view virtual override returns (uint256) {
        // Check for zero numerator to save gas
        uint256 numerator = quorumNumerator(timepoint);
        if (numerator == 0) {
            return 0;
        }
        return (_token.getPastTotalSupply(timepoint) * quorumNumerator(timepoint)) / quorumDenominator();
    }

    /**
     * @dev Changes the quorum numerator.
     *
     * Emits a {QuorumNumeratorUpdated} event.
     *
     * Requirements:
     *
     * - Must be called through a governance proposal.
     * - New numerator must be smaller or equal to the denominator.
     */
    function updateQuorumNumerator(uint256 newQuorumNumerator) external virtual onlyGovernance {
        _updateQuorumNumerator(newQuorumNumerator);
    }

    /**
     * @dev Changes the quorum numerator.
     *
     * Emits a {QuorumNumeratorUpdated} event.
     *
     * Requirements:
     *
     * - New numerator must be smaller or equal to the denominator.
     */
    function _updateQuorumNumerator(uint256 newQuorumNumerator) internal virtual {
        require(
            newQuorumNumerator <= quorumDenominator(),
            "GovernorVotesQuorumFraction: quorumNumerator over quorumDenominator"
        );

        uint256 oldQuorumNumerator = quorumNumerator();

        // Make sure we keep track of the original numerator in contracts upgraded from a version without checkpoints.
        if (oldQuorumNumerator != 0 && _quorumNumeratorCheckpoints.length() == 0) {
            _quorumNumeratorCheckpoints._checkpoints.push(
                Checkpoints.Checkpoint224({_key: 0, _value: oldQuorumNumerator.toUint224()})
            );
        }

        // Set new quorum for future proposals
        _quorumNumeratorCheckpoints.push(clock().toUint32(), newQuorumNumerator.toUint224());

        emit QuorumNumeratorUpdated(oldQuorumNumerator, newQuorumNumerator);
    }
}
