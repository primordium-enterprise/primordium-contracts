// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

/**
 * @title Interface functions used by the Treasurer for creating token distributions.
 * @author Ben Jett - @BCJdevelopment
 */
interface IDistributor {
    function initialize(address token_, uint256 claimPeriod_) external;

    function createDistribution(
        uint256 clockStartTime,
        IERC20 asset,
        uint256 amount
    )
        external
        payable
        returns (uint256 distributionId);
}
