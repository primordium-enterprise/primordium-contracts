// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ITreasury - The interface required for the token contract to facilitate deposits and withdrawals.
 * @author Ben Jett - @benbcjdev
 */
interface ITreasury {
    /**
     * @dev Emitted when a deposit is registered on the treasury.
     */
    event DepositRegistered(address indexed account, IERC20 quoteAsset, uint256 depositAmount, uint256 mintAmount);

    /**
     * @dev Emitted when a withdrawal is processed on the treasury.
     */
    event WithdrawalProcessed(
        address indexed account,
        address receiver,
        uint256 sharesBurned,
        uint256 totalSharesSupply,
        IERC20[] assets,
        uint256[] payouts
    );

    /**
     * @notice Registers a deposit on the treasury.
     * @dev This function is expected to mint the shares, which means this contract should have the required permissions
     * to mint shares on the token contract.
     * @param account The account to mint shares to.
     * @param quoteAsset The ERC20 asset that is being deposited. address(0) for native currency (such as ETH).
     * @param depositAmount The amount being deposited.
     * @param mintAmount The amount of shares to mint to the account.
     */
    function registerDeposit(
        address account,
        IERC20 quoteAsset,
        uint256 depositAmount,
        uint256 mintAmount
    )
        external
        payable;

    /**
     * @notice Processes a withdrawal to the withdrawing member.
     * @param receiver The address to send the shares of the treasury to.
     * @param sharesBurned The amount of share tokens being burned.
     * @param sharesTotalSupply The total supply of share tokens before the burning the withdraw amount.
     * @param tokens A list of ERC20 token addresses to send pro rata shares of. Uses address(0) for native currency
     * (such as ETH).
     */
    function processWithdrawal(
        address account,
        address receiver,
        uint256 sharesBurned,
        uint256 sharesTotalSupply,
        IERC20[] calldata tokens
    )
        external;
}
