// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "../Treasurer.sol";

abstract contract TreasurerETH is Treasurer {

    constructor() {
        require(address(_baseAsset) == address(0), "TreasurerETH: Invalid baseAsset address");
    }

    /// @dev Defaults to returning the ETH balance of this address
    function _treasuryBalance() internal view virtual override returns (uint256) {
        return address(this).balance;
    }

    /// @dev Override to ensure that the depositAmount is equal to the msg.value
    function _registerDeposit(uint256 depositAmount) internal virtual override {
        super._registerDeposit(depositAmount);
        require(msg.value == depositAmount, "TreasurerETH: mismatching depositAmount and msg.value");
    }

    /// @dev Override to process sending the ETH to the receiver
    function _processWithdrawal(address receiver, uint256 withdrawAmount) internal virtual override {
        super._processWithdrawal(receiver, withdrawAmount);
        (bool success,) = receiver.call{value: withdrawAmount}("");
        if (!success) revert("TreasurerETH: Failed to process ETH withdrawal");
    }

}