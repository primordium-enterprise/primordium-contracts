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

    // The total balance of the base asset that is not actually owned by the DAO (it is owed to BalanceShares, etc.)
    uint256 _stashedBalance;

    error InsufficientBaseAssetFunds(uint256 balanceTransferAmount, uint256 currentBalance);
    error InvalidBaseAssetOperation();

    /**
     * @dev Override to retrieve the base asset balance available to the DAO.
     */
    function _treasuryBalance() internal view virtual override returns (uint256) {
        return _mockUpdateTreasuryBalance(_currentTreasuryBalance(), _balance);
    }

    function updateTreasuryBalance() public returns (uint256) {
        return _updateTreasuryBalance();
    }

    /// @dev Helper function to return the current raw base asset balance minus the _stashedBalance
    function _currentTreasuryBalance() internal view virtual returns (uint256) {
        return _getBaseAssetBalance() - _stashedBalance;
    }

    /// @dev Update function that balances the treasury based on any revenue changes that occurred since the last update
    function _updateTreasuryBalance() internal virtual returns (uint256) {
        uint currentBalance = _currentTreasuryBalance();
        uint prevBalance = _balance;
        // If revenue occurred, apply revenue shares and update the balances
        if (currentBalance > prevBalance) {
            uint increasedBy = currentBalance - prevBalance;
            // Use "processBalanceShares" function to account for the remainder
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
            currentBalance -= _balanceShares[BalanceShareId.Revenue].calculateBalanceToAddToShares(increasedBy);
        }
        return currentBalance;
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

    /**
     * @dev Before execution of any action on the Executor, confirm that balance transfers do not exceed DAO balance and
     * update the balance accordingly
     */
    function _beforeExecute(address target, uint256 value, bytes calldata data) internal virtual override {
        super._beforeExecute(target, value, data);
        uint transferAmount = _checkExecutionBalanceTransfer(target, value, data);
        if (transferAmount > 0) {
            uint currentBalance = _treasuryBalance();
            // Revert if the attempted transfer amount is greater than the currentBalance
            if (transferAmount > _treasuryBalance()) {
                revert InsufficientBaseAssetFunds(transferAmount, currentBalance);
            }
            // Proactively update the treasury balance in anticipation of the base asset transfer
            _balance -= transferAmount;
        }
    }

    function _checkExecutionBalanceTransfer(
        address target,
        uint256 value,
        bytes calldata data
    ) internal virtual returns (uint256 balanceBeingTransferred);

}