// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "../Treasurer.sol";
import "contracts/governance/utils/BalanceShares.sol";

abstract contract TreasurerBalanceShares is Treasurer {

    using BalanceShares for BalanceShares.BalanceShare;
    BalanceShares.BalanceShare private _balanceShares;

    // The previously measured DAO balance (minus any _stashedBalance), for tracking changes to the balance amount
    uint256 _balance;

    // The total balance of the base asset that is not actually owned by the DAO (because it is owed to BalanceShares)
    uint256 _stashedBalance;

    function _treasuryBalance() internal view virtual override returns (uint256) {
        return _getBaseAssetBalance() - _stashedBalance;
    }

    function updateTreasuryBalance() public returns (uint256) {
        return _updateTreasuryBalance();
    }

    /// @dev Update function that balances the treasury based on any changes that occurred since the last update
    function _updateTreasuryBalance() internal virtual returns (uint256) {
        uint currentBalance = _getBaseAssetBalance();
        uint prevBalance = _balance;
    }

    /**
     * @dev Internal function to return the total base asset owned by this address (should be overridden depending on
     * the base asset type)
     */
    function _getBaseAssetBalance() internal view virtual returns (uint256);

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