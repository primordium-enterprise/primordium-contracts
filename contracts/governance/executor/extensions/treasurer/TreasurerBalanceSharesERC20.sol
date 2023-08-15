// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.4;

import "./TreasurerERC20.sol";
import "./TreasurerBalanceShares.sol";

abstract contract TreasurerBalanceSharesERC20 is TreasurerERC20, TreasurerBalanceShares {

    /**
     * @dev IMPORTANT to return the TreasurerBalanceShares function, as this is where BalanceShares internal accounting
     * occurs
     */
    function _treasuryBalance() internal view virtual override(Treasurer, TreasurerBalanceShares) returns (uint256) {
        return TreasurerBalanceShares._treasuryBalance();
    }

    function _registerDeposit(
        uint256 depositAmount
    ) internal virtual override(Treasurer, TreasurerBalanceShares) {
        super._registerDeposit(depositAmount);
    }

}