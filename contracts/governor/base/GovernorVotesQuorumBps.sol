// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts (last updated v4.8.0) (extensions/GovernorVotesQuorumBps.sol)

pragma solidity ^0.8.20;

import "./GovernorVotes.sol";
import "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @dev Extension of {GovernorBase} for voting weight extraction from an {ERC20Votes} token and a quorum expressed as a
 * fraction of the total supply, in basis points.
 *
 * The DAO can set the {quorumBps} to zero to allow any vote to pass without a quorum.
 *
 * _Available since v4.3._
 */
abstract contract GovernorVotesQuorumBps is GovernorVotes {

    using SafeCast for *;
    using Checkpoints for Checkpoints.Trace224;

    uint256 constant private MAX_BPS = 10_000;

    Checkpoints.Trace224 private _quorumBpsCheckpoints;

    event QuorumBpsUpdated(uint256 oldQuorumBps, uint256 newQuorumBps);

    error QuorumBpsTooLarge();

    /**
     * @dev Initialize quorum as a fraction of the token's total supply.
     *
     * The fraction is specified as `bps / 10_000`. So, the quorum is specified as a percent: a bps of 1_000 corresponds
     * to quorum being 10% of total supply.
     */
    constructor(uint256 quorumBps_) {
        _updateQuorumBps(quorumBps_);
    }

    /**
     * @dev Returns the current quorum bps.
     */
    function quorumBps() public view virtual returns (uint256) {
        return _quorumBpsCheckpoints.latest();
    }

    /**
     * @dev Returns the quorum bps at a specific timepoint.
     */
    function quorumBps(uint256 timepoint) public view virtual returns (uint256) {
        // Optimistic search, check the latest checkpoint
        (bool exists, uint256 _key, uint256 _value) = _quorumBpsCheckpoints.latestCheckpoint();
        if (exists && _key <= timepoint) {
            return _value;
        }

        // Otherwise, do the binary search
        return _quorumBpsCheckpoints.upperLookupRecent(timepoint.toUint32());
    }

    /**
     * @dev Returns the quorum for a timepoint, in terms of number of votes: `supply * bps / denominator`.
     */
    function quorum(uint256 timepoint) public view virtual override returns (uint256) {
        // Check for zero bps to save gas
        uint256 bps = quorumBps(timepoint);
        if (bps == 0) return 0;
        // NOTE: We don't need Math.mulDiv for overflow AS LONG AS the max supply of the token is <= type(uint224).max
        return (ERC20CheckpointsUpgradeable(_token).getPastTotalSupply(timepoint) * quorumBps(timepoint)) / MAX_BPS;
    }

    /**
     * @dev Changes the quorum bps.
     *
     * Emits a {QuorumBpsUpdated} event.
     *
     * Requirements:
     *
     * - Must be called through a governance proposal.
     * - New bps must be smaller or equal to 10_000.
     */
    function updateQuorumBps(uint256 newQuorumBps) external virtual onlyGovernance {
        _updateQuorumBps(newQuorumBps);
    }

    /**
     * @dev Changes the quorum bps.
     *
     * Emits a {QuorumBpsUpdated} event.
     *
     * Requirements:
     *
     * - New bps must be smaller or equal to 10_000.
     */
    function _updateQuorumBps(uint256 newQuorumBps) internal virtual {
        if (newQuorumBps > MAX_BPS) revert QuorumBpsTooLarge();

        uint256 oldQuorumBps = quorumBps();

        // Make sure we keep track of the original bps in contracts upgraded from a version without checkpoints.
        if (oldQuorumBps != 0 && _quorumBpsCheckpoints.length() == 0) {
            _quorumBpsCheckpoints._checkpoints.push(
                Checkpoints.Checkpoint224({_key: 0, _value: oldQuorumBps.toUint224()})
            );
        }

        // Set new quorum for future proposals
        _quorumBpsCheckpoints.push(clock().toUint32(), newQuorumBps.toUint224());

        emit QuorumBpsUpdated(oldQuorumBps, newQuorumBps);
    }
}
