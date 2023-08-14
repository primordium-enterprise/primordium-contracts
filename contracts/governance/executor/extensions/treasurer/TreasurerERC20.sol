// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.4;

import "../Treasurer.sol";

abstract contract TreasurerERC20 is Treasurer {

    constructor() {
        require(address(_baseAsset) != address(0));
    }

    /// @dev Override to return the raw base asset balance of this address with an ERC20 as the base asset
    function _baseAssetBalance() internal view virtual override returns (uint256) {
        return _baseAsset.balanceOf(address(this));
    }

    /// @dev Transfers ERC20 base asset
    function _transferBaseAsset(address to, uint256 amount) internal virtual override {
        SafeERC20.safeTransfer(_baseAsset, to, amount);
    }

}