// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "../Treasurer.sol";
import "contracts/governance/utils/BalanceShares.sol";

abstract contract TreasurerBalanceShares is Treasurer {

    using BalanceShares for BalanceShares.BalanceShare;
    enum BalanceShareId {
        Deposits,
        Revenue
    }
    mapping(BalanceShareId => BalanceShares.BalanceShare) private _balanceShares;

    // The previously measured DAO balance (minus any _stashedBalance), for tracking changes to the balance amount
    uint256 _balance;

    // The total balance of the base asset that is not actually owned by the DAO (because it is owed to BalanceShares)
    uint256 _stashedBalance;

    /**
     * @dev Override to retrieve the base asset balance available to the DAO.
     */
    function _treasuryBalance() internal view virtual override returns (uint256) {
        return _balance;
    }

    function updateTreasuryBalance() public returns (uint256) {
        return _updateTreasuryBalance();
    }

    /// @dev Update function that balances the treasury based on any revenue changes that occurred since the last update
    function _updateTreasuryBalance() internal virtual returns (uint256) {
        uint currentBalance = _getBaseAssetBalance() - _stashedBalance;
        uint prevBalance = _balance;
        // If revenue occurred, apply revenue shares and update the balances
        if (currentBalance > prevBalance) {
            uint increasedBy = currentBalance - prevBalance;
            uint stashed = _balanceShares[BalanceShareId.Revenue].processBalanceShares(increasedBy);
            _stashedBalance += stashed;
            currentBalance -= stashed;
            _balance = currentBalance;
        }
        return currentBalance;
    }

    function _mockUpdateTreasuryBalance(
        uint256 currentBalance,
        uint256 prevBalance
    ) internal view virtual returns (uint256) {
        if (currentBalance > prevBalance) {
            uint increasedBy = currentBalance - prevBalance;
            uint stashed = BalanceShares.calculateBalanceShare(
                increasedBy,
                _balanceShares[BalanceShareId.Revenue].totalBps()
            );
        }
    }

    /**
     * @dev Internal function to return the total base asset owned by this address (should be overridden depending on
     * the base asset type)
     */
    function _getBaseAssetBalance() internal view virtual returns (uint256);

    /// @dev Override to implement balance updates on the treasury for deposit shares
    function _registerDeposit(uint256 depositAmount) internal virtual override {
        super._registerDeposit(depositAmount);
        // NEED TO BYPASS UNTIL INITIALIZATION, THEN APPLY RETROACTIVELY
        uint stashed = _balanceShares[BalanceShareId.Deposits].processBalanceShares(depositAmount);
        _balance += depositAmount - stashed;
        _stashedBalance += stashed;
    }

    /// @dev Override to implement balance updates on the treasury
    function _processWithdrawal(address receiver, uint256 withdrawAmount) internal virtual override {
        // UPDATE TREASURY BALANCE FIRST
        super._processWithdrawal(receiver, withdrawAmount);
        // BALANCE CHECKS
        _balance -= withdrawAmount;
    }

}