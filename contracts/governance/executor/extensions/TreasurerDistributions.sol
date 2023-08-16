// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.4;

import "./Treasurer.sol";

abstract contract TreasurerDistributions is Treasurer {

    /**
     * @notice The maximum claim period for new distributions.
     */
    uint256 public immutable MAX_DISTRIBUTION_CLAIM_PERIOD;
    /**
     * @notice The minimum claim period for new distributions.
     */
    uint256 public immutable MIN_DISTRIBUTION_CLAIM_PERIOD;

    // Distributions counter
    uint256 public distributionsCount;

    struct Distribution {
        uint32 clockStartDate; // The ERC20Checkpoints clock date that this distribution should begin
        uint224 cachedTotalSupply;

        bool closed;

        uint256 balance;
        uint256 claimedBalance;
    }

    mapping(uint256 => Distribution) _distributions;

    constructor() {
        // Initialize immutables based on clock (assums block.timestamp if not block.number)
        bool usesBlockNumber = clock() == block.number;
        MAX_DISTRIBUTION_CLAIM_PERIOD = usesBlockNumber ?
            1_209_600 : // About 24 weeks at 12sec/block
            24 weeks;
        MIN_DISTRIBUTION_CLAIM_PERIOD = usesBlockNumber ?
            201_600 : // About 4 weeks at 12sec/block
            4 weeks;
    }

    error ClockStartDateOutOfRange();

    function createDistribution(
        uint256 clockStartDate,
        uint256 distributionBalance
    ) external virtual onlyTimelock {
        uint currentClock = clock();
        if (clockStartDate == 0) {
            clockStartDate = currentClock - 1;
        } else if (clockStartDate <= currentClock) {
            revert ClockStartDateOutOfRange();
        }

    }

}