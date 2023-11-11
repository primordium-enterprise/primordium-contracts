// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";

/**
 * @dev Additional interface methods for {ERC20CheckpointsUpgradeable}.
 */
interface IERC20Checkpoints is IERC20, IERC6372 {

    error ERC20CheckpointsFutureLookup(uint256 currentClock);
    error ERC20CheckpointsMaxSupplyOverflow(uint256 maxSupply, uint256 resultingSupply);

    /**
     * @dev Maximum token supply. Should default to (and never be greater than) `type(uint224).max` (2^224^ - 1).
     */
    function maxSupply() external view returns (uint256);

    /**
     * @dev Returns the total supply of votes available at a specific moment in the past. If the `clock()` is
     * configured to use block numbers, this will return the value the end of the corresponding block.
     *
     * NOTE: This value is the sum of all available votes, which is not necessarily the sum of all delegated votes.
     * Votes that have not been delegated are still part of total supply, even though they would not participate in a
     * vote.
     */
    function getPastTotalSupply(uint256 timepoint) external view returns (uint256);

    /**
     * @dev Additional method to check the balance of tokens for `account` at the end of `timepoint`.
     *
     * Requirements:
     *
     * - `timepoint` must be in the past
     */
    function getPastBalanceOf(address account, uint256 timepoint) external view returns (uint256);

}