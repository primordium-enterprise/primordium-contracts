// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

interface IBalanceSharesManager {

    function getBalanceShareTotalBPS(
        uint256 balanceShareId
    ) external view returns (uint256 totalBps);

    function getBalanceShareAllocation(
        uint256 balanceShareId,
        IERC20 asset,
        uint256 balanceIncreasedBy
    ) external view returns (uint256 amountToAllocate);

    function getBalanceShareAllocationWithRemainder(
        uint256 balanceShareId,
        IERC20 asset,
        uint256 balanceIncreasedBy
    ) external view returns (uint256 amountToAllocate, bool remainderIncrease);

    function allocateToBalanceShare(
        uint256 balanceShareId,
        IERC20 asset,
        uint256 amountToAllocate
    ) external payable;

    function allocateToBalanceShareWithRemainder(
        uint256 balanceShareId,
        IERC20 asset,
        uint256 balanceIncreasedBy
    ) external payable;

}