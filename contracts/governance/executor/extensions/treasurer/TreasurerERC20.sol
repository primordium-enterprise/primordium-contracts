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

    /// @dev Override to process sending the ERC20 to the receiver
    function _processWithdrawal(address receiver, uint256 withdrawAmount) internal virtual override {
        super._processWithdrawal(receiver, withdrawAmount);
        SafeERC20.safeTransfer(_baseAsset, receiver, withdrawAmount);
    }

}