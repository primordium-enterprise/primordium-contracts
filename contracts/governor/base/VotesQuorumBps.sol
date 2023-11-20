// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts (last updated v4.8.0) (extensions/GovernorVotesQuorumBps.sol)

pragma solidity ^0.8.20;

import {GovernorBase} from "./GovernorBase.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {BasisPoints} from "contracts/libraries/BasisPoints.sol";

/**
 * @title VotesQuorumBps
 *
 * @dev Extension of {GovernorBase} for voting weight extraction from an {ERC20Votes} token and a quorum expressed as a
 * fraction of the total supply, in basis points.
 *
 * The DAO can set the {quorumBps} to zero to allow any vote to pass without a quorum.
 *
 * @author Ben Jett - @BCJdevelopment
 */
abstract contract VotesQuorumBps is GovernorBase {
    using SafeCast for *;
    using Checkpoints for Checkpoints.Trace208;
    using BasisPoints for uint256;

    /// @custom:storage-location erc7201:VotesQuorumBps.Storage
    struct VotesQuorumBpsStorage {
        Checkpoints.Trace208 _quorumBpsCheckpoints;
    }

    bytes32 private immutable VOTES_QUORUM_BPS_STORAGE =
        keccak256(abi.encode(uint256(keccak256("VotesQuorumBps.Storage")) - 1)) & ~bytes32(uint256(0xff));

    function _getVotesQuorumBpsStorage() private view returns (VotesQuorumBpsStorage storage $) {
        bytes32 slot = VOTES_QUORUM_BPS_STORAGE;
        assembly {
            $.slot := slot
        }
    }

    event QuorumBpsUpdated(uint256 oldQuorumBps, uint256 newQuorumBps);

    error QuorumBpsTooLarge();

    /**
     * @dev Initialize quorum as a fraction of the token's total supply.
     *
     * The fraction is specified as `bps / 10_000`. So, the quorum is specified as a percent: a bps of 1_000 corresponds
     * to quorum being 10% of total supply.
     */
    function __VotesQuorumBps_init(
        uint256 quorumBps_
    ) internal virtual onlyInitializing {
        _setQuorumBps(quorumBps_);
    }

    /**
     * @dev Returns the current quorum bps.
     */
    function quorumBps() public view virtual returns (uint256) {
        return _getVotesQuorumBpsStorage()._quorumBpsCheckpoints.latest();
    }

    /**
     * @dev Returns the quorum bps at a specific timepoint.
     */
    function quorumBps(uint256 timepoint) public view virtual returns (uint256) {
        // Optimistic search, check the latest checkpoint
        VotesQuorumBpsStorage storage $ = _getVotesQuorumBpsStorage();
        (bool exists, uint256 _key, uint256 _value) = $._quorumBpsCheckpoints.latestCheckpoint();
        if (exists && _key <= timepoint) {
            return _value;
        }

        // Otherwise, do the binary search
        return $._quorumBpsCheckpoints.upperLookupRecent(timepoint.toUint48());
    }

    /**
     * @dev Returns the quorum for a timepoint, in terms of number of votes: `supply * bps / denominator`.
     */
    function quorum(uint256 timepoint) public view virtual override returns (uint256) {
        // Check for zero bps to save gas
        uint256 _quorumBps = quorumBps(timepoint);
        if (_quorumBps == 0) return 0;
        // NOTE: We don't need to check for overflow AS LONG AS the max supply of the token is <= type(uint224).max
        return token().getPastTotalSupply(timepoint).bpsUnchecked(_quorumBps);
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
    function setQuorumBps(uint256 newQuorumBps) external virtual onlyGovernance {
        _setQuorumBps(newQuorumBps);
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
    function _setQuorumBps(uint256 newQuorumBps) internal virtual {
        if (newQuorumBps > BasisPoints.MAX_BPS) revert QuorumBpsTooLarge();

        uint256 oldQuorumBps = quorumBps();

        // Set new quorum for future proposals
        VotesQuorumBpsStorage storage $ = _getVotesQuorumBpsStorage();
        $._quorumBpsCheckpoints.push(clock(), uint208(newQuorumBps));

        emit QuorumBpsUpdated(oldQuorumBps, newQuorumBps);
    }
}
