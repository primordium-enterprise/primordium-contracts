// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.4;

import "./GovernorCountingSimple.sol";
import "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

abstract contract GovernorCountingPercentMajority is GovernorCountingSimple {

    using SafeCast for *;
    using Checkpoints for Checkpoints.Trace224;

    Checkpoints.Trace224 private _percentMajorityCheckpoints;

    uint256 constant private MAX_PERCENT = 100;
    uint256 public constant MIN_PERCENT_MAJORITY = 50;
    uint256 public constant MAX_PERCENT_MAJORITY = 66;

    event PercentMajorityUpdated(uint256 oldPercentMajority, uint256 newPercentMajority);

    error PercentMajorityOutOfRange(uint256 minRange, uint256 maxRange);

    constructor(uint256 percentMajority_) {
        _updatePercentMajority(percentMajority_);
    }

    /**
     * @notice Returns the current percent majority required for passing proposals.
     */
    function percentMajority() public view virtual returns (uint256) {
        return _percentMajorityCheckpoints.latest();
    }

    /**
     * @notice Returns the percent majority at the specified timepoint.
     * @param timepoint The timepoint according to the clock mode of the Governor.
     */
    function percentMajority(uint256 timepoint) public view virtual returns (uint256) {
        return _percentMajority(timepoint);
    }

    /**
     * @notice A method to update the percent majority for future proposals. Only setable through governance.
     */
    function updatePercentMajority(uint256 newPercentMajority) public virtual onlyGovernance {
        _updatePercentMajority(newPercentMajority);
    }

    /**
     * @dev In this module, the percentage of forVotes must be greater than the
     * percentMajority value at the proposal snapshot.
     */
    function _voteSucceeded(uint256 proposalId) internal view virtual override returns (bool) {
        (
            uint256 percentToSucceed,
            uint256 againstVotes,
            uint256 forVotes
        ) = _getVoteCalculationParams(proposalId);

        /**
         * (percentToSucceed / 100) < forVotes / (forVotes + againstVotes)
         * which becomes...
         * percentToSucceed < (forVotes * 100) / (forVotes + againstVotes)
         */

        uint256 numerator = forVotes * MAX_PERCENT;
        uint256 denominator = againstVotes + forVotes;

        // Find the division result.
        uint256 divResult = numerator / denominator;
        // If greater than the minimum percent, then it succeeded
        if (divResult > percentToSucceed) return true;
        // If equal, check the remainder
        if (divResult == percentToSucceed) {
            uint256 remainder = numerator % denominator;
            // If there is a remainder, then it succeeded
            if (remainder > 0) return true;
        }
        // Otherwise, return false
        return false;
    }

    /**
     * @dev In this module, the vote margin is calculated as the distance of the current forVotes from the tipping point
     * number of forVotes based on the percentMajority value at the proposal snapshot.
     */
    function _voteMargin(uint256 proposalId) internal view virtual override returns (uint256) {
        (
            uint256 percentToSucceed,
            uint256 againstVotes,
            uint256 forVotes
        ) = _getVoteCalculationParams(proposalId);

        /**
         * forVotesToSucceed / (forVotesToSucceed + againstVotes) = percentToSucceed / 100
         * which after some rearranging becomes...
         * forVotesToSucceed = (percentToSucceed * againstVotes) / (100 - percentToSucceed)
         */

        // If the againstVotes is zero, then the margin is just the forVotes
        if (againstVotes == 0) {
            return forVotes;
        }
        uint256 numerator = percentToSucceed * againstVotes;
        uint256 denominator = MAX_PERCENT - percentToSucceed;
        uint256 forVotesToTipScales = numerator / denominator;
        // If there is a remainder, we need to add 1 to the result
        if (numerator % denominator > 0) {
            forVotesToTipScales += 1;
        }
        return forVotes > forVotesToTipScales ? forVotes - forVotesToTipScales : forVotesToTipScales - forVotes;
    }

    /**
     * @dev An internal helper function for getting the vote calculation parameters percentToSucceed, againstVotes, and
     * forVotes
     * @return percentToSucceed The percent majority required for this proposal.
     * @return againstVotes The number of votes against the proposal
     * @return forVotes The number of votes for the proposal
     */
    function _getVoteCalculationParams(uint256 proposalId) internal view virtual returns (uint256, uint256, uint256) {
        uint256 percentToSucceed = _percentMajority(proposalSnapshot(proposalId));
        (
            uint256 againstVotes,
            uint256 forVotes
        ) = _proposalCountedVotes(proposalId);
        return (percentToSucceed, againstVotes, forVotes);
    }

    /**
     * @dev Helper method to return the percent majority at the specified timepoint.
     */
    function _percentMajority(uint256 timepoint) internal view virtual returns (uint256) {
        // Optimistic search, check the latest checkpoint
        (bool exists, uint256 _key, uint256 _value) = _percentMajorityCheckpoints.latestCheckpoint();
        if (exists && _key <= timepoint) {
            return _value;
        }

        // Otherwise, do the binary search
        return _percentMajorityCheckpoints.upperLookupRecent(timepoint.toUint32());
    }

    /**
     * @dev Helper method to create a new percent majority checkpoint.
     */
    function _updatePercentMajority(uint256 newPercentMajority) internal virtual {
        if (
            newPercentMajority < MIN_PERCENT_MAJORITY ||
            newPercentMajority > MAX_PERCENT_MAJORITY
        ) revert PercentMajorityOutOfRange(MIN_PERCENT_MAJORITY, MAX_PERCENT_MAJORITY);

        uint256 oldPercentMajority = percentMajority();

        // Make sure we keep track of the original in contracts upgraded from a version without checkpoints.
        if (oldPercentMajority != 0 && _percentMajorityCheckpoints.length() == 0) {
            _percentMajorityCheckpoints._checkpoints.push(
                Checkpoints.Checkpoint224({_key: 0, _value: oldPercentMajority.toUint224()})
            );
        }

        // Set new percent majority for future proposals
        _percentMajorityCheckpoints.push(clock().toUint32(), uint224(newPercentMajority));

        emit PercentMajorityUpdated(oldPercentMajority, newPercentMajority);
    }
}