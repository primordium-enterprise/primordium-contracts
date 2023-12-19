// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

interface IGuardable {
    function setGuard(address guard) external;

    function getGuard() external view returns (address guard);
}
