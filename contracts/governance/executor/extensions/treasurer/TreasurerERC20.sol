// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "../Treasurer.sol";

abstract contract TreasurerERC20 is Treasurer {

    constructor() {
        require(address(_baseAsset) != address(0));
    }

}