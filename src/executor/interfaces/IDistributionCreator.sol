// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Interface functions used by the Treasurer for creating token distributions.
 * @author Ben Jett - @benbcjdev
 */
interface IDistributionCreator {
    function setUp(bytes memory initParams) external;

    /**
     * Creates a new distribution for share holders.
     * @notice Only callable by the owner (see dev note about authorized operation).
     * @param snapshotId The ID of the token snapshot for this distribution.
     * @param asset The ERC20 asset to be used for the distribution (address(0) for ETH).
     * @param amount The amount of the ERC20 asset to be transferred to this contract as a total amount avaialable for
     * distribution. Cannot be greater than type(uint128).max for gas reasons.
     * @return distributionId The ID of the newly created distribution.
     */
    function createDistribution(
        uint256 snapshotId,
        IERC20 asset,
        uint256 amount
    )
        external
        payable
        returns (uint256 distributionId);
}
