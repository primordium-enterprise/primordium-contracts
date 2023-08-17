// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.4;

import "./Treasurer.sol";
import "@openzeppelin/contracts/utils/Checkpoints.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

abstract contract TreasurerDistributions is Treasurer {

    using SafeCast for *;
    using Checkpoints for Checkpoints.Trace224;

    event DistributionCreated(uint256 distributionId, uint256 clockStartTime, uint256 distributionBalance);
    event DistributionClaimPeriodUpdated(uint256 oldClaimPeriod, uint256 newClaimPeriod);

    /**
     * @notice The maximum claim period for new distributions.
     */
    uint256 public immutable MAX_DISTRIBUTION_CLAIM_PERIOD;
    /**
     * @notice The minimum claim period for new distributions.
     */
    uint256 public immutable MIN_DISTRIBUTION_CLAIM_PERIOD;

    // The claim period for distributions, after which the Timelock can close the distribution to reclaim leftover funds.
    Checkpoints.Trace224 private _claimPeriodCheckpoints;

    // Distributions counter
    uint256 public distributionsCount;

    struct Distribution {
        uint32 clockStartTime; // The ERC20Checkpoints clock date that this distribution should begin
        uint224 cachedTotalSupply;
        uint256 balance;
        uint256 claimedBalance;
    }

    mapping(uint256 => Distribution) _distributions;

    mapping(uint256 => bool) _closedDistributions;

    constructor(uint256 distributionClaimPeriod_) {
        // Initialize immutables based on clock (assums block.timestamp if not block.number)
        bool usesBlockNumber = clock() == block.number;
        MAX_DISTRIBUTION_CLAIM_PERIOD = usesBlockNumber ?
            1_209_600 : // About 24 weeks at 12sec/block
            24 weeks;
        MIN_DISTRIBUTION_CLAIM_PERIOD = usesBlockNumber ?
            201_600 : // About 4 weeks at 12sec/block
            4 weeks;

        _updateDistributionClaimPeriod(distributionClaimPeriod_);
    }

    /**
     * @notice Creates a new distribution. Only callable by the Timelock itself.
     * @param clockStartTime The start timepoint (according to the token clock) when this distribution will become
     * active. Must be in the future (or will be set to the current execution timepoint if set to zero).
     * @param distributionBalance The balance to be set aside as a distribution, claimable by all token holders according
     * to their token balance at the clockStartTime.
     */
    function createDistribution(
        uint256 clockStartTime,
        uint256 distributionBalance
    ) external virtual onlyTimelock returns (uint256) {
        return _createDistribution(clockStartTime, distributionBalance);
    }

    error ClockStartDateOutOfRange();
    error DistributionBalanceTooLow();
    /**
     * @dev Internal function to create a new distribution.
     */
    function _createDistribution(
        uint256 clockStartTime,
        uint256 distributionBalance
    ) internal virtual returns (uint256) {
        uint currentClock = clock();

        if (clockStartTime == 0) {
            clockStartTime = currentClock;
        } else if (clockStartTime <= currentClock) {
            revert ClockStartDateOutOfRange();
        }

        if (distributionBalance == 0) revert DistributionBalanceTooLow();

        uint currentTreasuryBalance = _treasuryBalance();
        if (distributionBalance > currentTreasuryBalance) revert InsufficientBaseAssetFunds(
            distributionBalance,
            currentTreasuryBalance
        );

        uint256 distributionId = ++distributionsCount;

        _distributions[distributionId] = Distribution({
            clockStartTime: clockStartTime.toUint32(),
            cachedTotalSupply: 0,
            balance: distributionBalance,
            claimedBalance: 0
        });

        // Transfer to the stash
        _transferBaseAssetToStash(distributionBalance);

        emit DistributionCreated(distributionId, clockStartTime, distributionBalance);

        return distributionId;
    }

    /**
     * @notice Returns the current distribution claim period.
     */
    function distributionClaimPeriod() public view virtual returns (uint256) {
        return _claimPeriodCheckpoints.latest();
    }

    /**
     * @notice Returns the distribution claim period at a specific timepoint.
     */
    function distributionClaimPeriod(uint256 timepoint) public view virtual returns (uint256) {
        // Optimistic search, check the latest checkpoint
        (bool exists, uint256 _key, uint256 _value) = _claimPeriodCheckpoints.latestCheckpoint();
        if (exists && _key <= timepoint) {
            return _value;
        }

        // Otherwise, do the binary search
        return _claimPeriodCheckpoints.upperLookupRecent(timepoint.toUint32());
    }

    /**
     * @notice Changes the distribution claim period.
     */
    function updateDistributionClaimPeriod(uint256 newClaimPeriod) external virtual onlyTimelock {
        _updateDistributionClaimPeriod(newClaimPeriod);
    }

    error DistributionClaimPeriodOutOfRange(uint256 min, uint256 max);
    /**
     * @dev Internal function to update the distribution claim period.
     */
    function _updateDistributionClaimPeriod(uint256 newClaimPeriod) internal virtual {
        if (
            newClaimPeriod < MIN_DISTRIBUTION_CLAIM_PERIOD ||
            newClaimPeriod > MAX_DISTRIBUTION_CLAIM_PERIOD
        ) revert DistributionClaimPeriodOutOfRange(MIN_DISTRIBUTION_CLAIM_PERIOD, MAX_DISTRIBUTION_CLAIM_PERIOD);

        uint256 oldClaimPeriod = distributionClaimPeriod();

        _claimPeriodCheckpoints.push(clock().toUint32(), newClaimPeriod.toUint224());

        emit DistributionClaimPeriodUpdated(oldClaimPeriod, newClaimPeriod);
    }

}