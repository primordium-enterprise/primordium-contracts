// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import "../base/Treasurer.sol";
import "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

abstract contract TreasurerDistributions is Treasurer {

    using SafeCast for *;
    using Checkpoints for Checkpoints.Trace224;

    struct Distribution {
        // The ERC20CheckpointsUpgradeable clock date that this distribution should begin
        uint32 clockStartTime;
        uint224 cachedTotalSupply;
        uint256 balance;
        uint256 claimedBalance;
        mapping(address => bool) hasClaimed;
    }

    // Distributions counter
    uint256 public distributionsCount;

    // The distribution claim period, after which the Timelock can close the distribution to reclaim leftover funds.
    Checkpoints.Trace224 private _claimPeriodCheckpoints;

    // Tracks all distributions
    mapping(uint256 => Distribution) private _distributions;

    // Tracks whether or not a distribution has been closed
    mapping(uint256 => bool) private _closedDistributions;


    event DistributionCreated(uint256 indexed distributionId, uint256 clockStartTime, uint256 distributionBalance);
    event DistributionClaimPeriodUpdated(uint256 oldClaimPeriod, uint256 newClaimPeriod);
    event DistributionClaimed(uint256 indexed distributionId, address indexed claimedFor, uint256 claimedAmount);
    event DistributionClosed(uint256 indexed distributionId, uint256 reclaimedAmount);

    error ClockStartDateOutOfRange();
    error DistributionBalanceTooLow();
    error DistributionIsClosed();
    error UnapprovedForClaimingDistribution();
    error AddressAlreadyClaimed();
    error UnapprovedForClosingDistributions();
    error DistributionClaimPeriodStillActive();
    error DistributionDoesNotExist();
    error DistributionHasNotStarted();
    error DistributionClaimPeriodOutOfRange(uint256 min, uint256 max);

    /**
     * @notice A public view function to see data about the specified distribution.
     * @param distributionId The identifier for the distribution to view.
     * @return isDistribitionClosed True if the distribution has been closed.
     * @return clockStartTime The start time (according to the token clock mode), after which this distribution will be
     * claimable.
     * @return distributionBalance The total balance available to token holders for this distribution.
     * @return claimedBalance The total balance that has been claimed by token holders for this distribution.
     */
    function getDistribution(uint256 distributionId) public view virtual returns(
        bool,
        uint256,
        uint256,
        uint256
    ) {
        Distribution storage distribution = _distributions[distributionId];
        uint256 clockStartTime = distribution.clockStartTime;
        if (clockStartTime == 0) revert DistributionDoesNotExist();
        return (
            _closedDistributions[distributionId],
            clockStartTime,
            distribution.balance,
            distribution.claimedBalance
        );
    }




    function _checkClockValidity(
        uint256 clockStartTime,
        uint256 currentClock
    ) private pure {
        if (clockStartTime == 0) revert DistributionDoesNotExist();
        if (currentClock <= clockStartTime) revert DistributionHasNotStarted();
    }

}