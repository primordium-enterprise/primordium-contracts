// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {ISharesManager} from "contracts/shares/interfaces/ISharesManager.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

/**
 * @title ITreasury - The interface required for the token contract to facilitate deposits and withdrawals.
 * @author Ben Jett - @BCJdevelopment
 */
interface ITreasury {

    function registerDeposit(IERC20 quoteAsset, uint256 depositAmount) external payable;

    function processWithdrawal(
        address receiver,
        uint256 withdrawAmount,
        uint256 totalSupply,
        IERC20[] calldata tokens
    ) external;

}