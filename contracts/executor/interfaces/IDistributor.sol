// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

/**
 * @title Interface functions used by the Treasurer for creating token distributions.
 * @author Ben Jett - @BCJdevelopment
 */
interface IDistributor {

    function initialize(
        address token_,
        uint256 claimPeriod_
    ) external;

    function createDistribution(
        uint256 clockStartTime,
        address asset,
        uint256 amount
    ) external payable returns (uint256 distributionId);

}