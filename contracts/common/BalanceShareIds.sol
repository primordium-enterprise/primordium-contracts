// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

abstract contract BalanceShareIds {

    uint256 public immutable DEPOSITS_ID = uint256(keccak256("deposits"));
    uint256 public immutable DISTRIBUTIONS_ID = uint256(keccak256("distributions"));

}