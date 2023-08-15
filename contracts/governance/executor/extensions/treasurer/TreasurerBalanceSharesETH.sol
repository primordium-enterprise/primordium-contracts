// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.4;

import "./TreasurerETH.sol";
import "./TreasurerBalanceShares.sol";

abstract contract TreasurerBalanceSharesETH is TreasurerETH, TreasurerBalanceShares {

    /**
     * @dev IMPORTANT to return the TreasurerBalanceShares function, as this is where BalanceShares internal accounting
     * occurs
     */
    function _treasuryBalance() internal view virtual override(Treasurer, TreasurerBalanceShares) returns (uint256) {
        return TreasurerBalanceShares._treasuryBalance();
    }

    function _registerDeposit(
        uint256 depositAmount
    ) internal virtual override(TreasurerETH, TreasurerBalanceShares) {
        super._registerDeposit(depositAmount);
    }

    function _processWithdrawal(
        address receiver,
        uint256 withdrawAmount
    ) internal virtual override(Treasurer, TreasurerBalanceShares) {
        super._processWithdrawal(receiver, withdrawAmount);
    }

}