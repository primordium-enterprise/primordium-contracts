// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "../Treasurer.sol";
import "contracts/governance/utils/BalanceShares.sol";

abstract contract TreasurerBalanceShares is Treasurer {

    using BalanceShares for BalanceShares.BalanceShare;
    BalanceShares.BalanceShare private _balanceShares;

    // The treasury balance accessible to the DAO (some funds may be allocated to BalanceShares)
    uint256 _balance;

    function _treasuryBalance() internal view virtual override returns (uint256) {
        return _balance;
    }

    function updateTreasuryBalance() public returns (uint256) {
        return _updateTreasuryBalance();
    }

    /// @dev Update function that balances the treasury based on any changes that occurred since the last update
    function _updateTreasuryBalance() internal virtual returns (uint256);

    /// @dev Override to implement balance updates on the treasury
    function _registerDeposit(uint256 depositAmount) internal virtual override {
        super._registerDeposit(depositAmount);
        // BALANCE CHECKS
        _balance += depositAmount;
    }

    /// @dev Override to implement balance updates on the treasury
    function _processWithdrawal(address receiver, uint256 withdrawAmount) internal virtual override {
        // UPDATE TREASURY BALANCE FIRST
        super._processWithdrawal(receiver, withdrawAmount);
        // BALANCE CHECKS
        _balance -= withdrawAmount;
    }

}