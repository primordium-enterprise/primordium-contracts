// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {ISharesManager} from "src/shares/interfaces/ISharesManager.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

/**
 * @title ITreasury - The interface required for the token contract to facilitate deposits and withdrawals.
 * @author Ben Jett - @BCJdevelopment
 */
interface ITreasury {
    /**
     * @dev Registers a deposit on the Treasury. Should only be callable by the shares contract.
     * @param quoteAsset The ERC20 asset that is being deposited. address(0) for native currency (such as ETH).
     * @param depositAmount The amount being deposited.
     */
    function registerDeposit(IERC20 quoteAsset, uint256 depositAmount) external payable;

    /**
     * @dev Processes a withdrawal from the Treasurer to the withdrawing member. Should only be callable by the shares
     * contract.
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
