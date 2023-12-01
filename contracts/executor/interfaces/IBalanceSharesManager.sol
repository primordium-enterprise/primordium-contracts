// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

interface IBalanceSharesManager {

    function getBalanceShareAllocation(
        uint256 balanceShareId,
        address asset,
        uint256 balanceIncreasedBy
    ) external view returns (uint256 amountToAllocate);

    function getBalanceShareAllocationWithRemainder(
        uint256 balanceShareId,
        address asset,
        uint256 balanceIncreasedBy
    ) external view returns (uint256 amountToAllocate, uint256 newAssetRemainder);

    function allocateToBalanceShare(
        uint256 balanceShareId,
        address asset,
        uint256 amountToAllocate
    ) external payable;

    function allocateToBalanceShareWithRemainder(
        uint256 balanceShareId,
        address asset,
        uint256 amountToAllocate,
        uint256 newAssetRemainder
    ) external payable;

}