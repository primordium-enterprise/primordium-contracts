// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "../Treasurer.sol";
import "contracts/governance/utils/BalanceShares.sol";

abstract contract TreasurerBalanceShares is Treasurer {

    using BalanceShares for BalanceShares.BalanceShare;
    BalanceShares.BalanceShare private _balanceShares;

    // The treasury balance accessible to the DAO (some funds may be allocated to BalanceShares)
    uint256 _treasuryBalance;

    /// @dev Override to implement balance updates on the treasury
    function _registerDeposit(uint256 depositAmount) internal virtual override {
        super._registerDeposit(depositAmount);
        // BALANCE CHECKS
    }

    /// @dev Override to implement balance updates on the treasury
    function _processWithdrawal(address receiver, uint256 withdrawAmount) internal virtual override {
        super._processWithdrawal(receiver, withdrawAmount);
        // BALANCE CHECKS
    }
}