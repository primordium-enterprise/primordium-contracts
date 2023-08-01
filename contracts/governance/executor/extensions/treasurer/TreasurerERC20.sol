// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "../Treasurer.sol";

abstract contract TreasurerERC20 is Treasurer {

    constructor() {
        require(address(_baseAsset) != address(0));
    }

    /// @dev Defaults to returning the base ERC20 asset balance of this address
    function _treasuryBalance() internal view virtual override returns (uint256) {
        return _baseAsset.balanceOf(address(this));
    }

    function _transferBaseAsset(address to, uint256 amount) internal virtual override {
        SafeERC20.safeTransfer(_baseAsset, to, amount);
    }

}