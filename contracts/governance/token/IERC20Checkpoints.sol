// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.4;

/**
 * @dev Additional interface methods for {ERC20Checkpoints}.
 */
interface IERC20Checkpoints {

    error FutureLookup(uint256 currentClock);
    error MaxSupplyOverflow(uint256 maxSupply, uint256 resultingSupply);

    // EIP-6093 ERC-20 errors
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InvalidSender(address sender);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ERC20InvalidApprover(address approver);
    error ERC20InvalidSpender(address spender);

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