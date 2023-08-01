// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "./TreasurerETH.sol";
import "./TreasurerBalanceShares.sol";

abstract contract TreasurerBalanceSharesETH is TreasurerETH, TreasurerBalanceShares {

    /**
     * @dev IMPORTANT to return the TreasurerBalanceShares function, as this is where BalanceShares internal accounting
     * occurs
     */
    function _treasuryBalance() internal view virtual override(TreasurerETH, TreasurerBalanceShares) returns (uint256) {
        return TreasurerBalanceShares._treasuryBalance();
    }

    function _beforeExecute(address target, uint256 value, bytes calldata data) internal virtual override {
        super._beforeExecute(target, value, data);
        if (value > 0) {
            // UPDATE BALANCE AND THEN ADJUST BASED ON ETH VALUE, DON'T ALLOW IF MORE THAN BALANCE
        }
    }

    function _updateTreasuryBalance() internal virtual override returns (uint256) {

    }

    function _registerDeposit(
        uint256 depositAmount
    ) internal virtual override(TreasurerETH, TreasurerBalanceShares) {
        super._registerDeposit(depositAmount);
    }

    function _processWithdrawal(
        address receiver,
        uint256 withdrawAmount
    ) internal virtual override(TreasurerETH, TreasurerBalanceShares) {
        super._processWithdrawal(receiver, withdrawAmount);
    }

}