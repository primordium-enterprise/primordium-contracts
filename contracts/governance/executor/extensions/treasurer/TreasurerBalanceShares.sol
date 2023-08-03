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
     *
     * Calculates any revenue shares that would need to be applied first (but doesn't save these to state in order to
     * save gas)
     */
    function _treasuryBalance() internal view virtual override returns (uint256) {
        uint256 currentBalance = _currentTreasuryBalance();
        uint256 prevBalance = _balance;
        if (currentBalance > prevBalance) {
            currentBalance -= _balanceShares[BalanceShareId.Revenue].calculateBalanceToAddToShares(
                currentBalance - prevBalance
            );
        }
        return currentBalance;
    }

    /**
     * @dev Helper function to return the full base asset balance minus the _stashedBalance
     */
    function _currentTreasuryBalance() internal view virtual returns (uint256) {
        return _getBaseAssetBalance() - _stashedBalance;
    }

    /**
     * @notice A publicly callable function to update the treasury balances, processing any revenue shares and saving
     * these updates to the contract state.
     */
    function processBalanceShares() public returns (uint256) {
        return _processBalanceShares();
    }

    /**
     * @dev Update function that balances the treasury based on any revenue changes that occurred since the last update.
     *
     * Saves these changes to the _balance and _stashedBalance storage state.
     *
     * Calls BalanceShares.processBalanceShare on the revenue shares to track any balance remainders as well.
     */
    function _processBalanceShares() internal virtual returns (uint256) {
        uint currentBalance = _currentTreasuryBalance();
        uint prevBalance = _balance;
        // If revenue occurred, apply revenue shares and update the balances
        if (currentBalance > prevBalance) {
            uint increasedBy = currentBalance - prevBalance;
            // Use "processBalanceShare" function to account for the remainder
            uint stashed = _balanceShares[BalanceShareId.Revenue].processBalanceShare(increasedBy);
            _stashedBalance += stashed;
            currentBalance -= stashed;
            _balance = currentBalance;
        }
        return currentBalance;
    }

    /**
     * @dev Internal function to return the total base asset owned by this address (needs to be overridden based on
     * the base asset type)
     */
    function _getBaseAssetBalance() internal view virtual returns (uint256);

    /// @dev Override to implement balance updates on the treasury for deposit shares
    function _registerDeposit(uint256 depositAmount) internal virtual override {
        super._registerDeposit(depositAmount);
        // NEED TO BYPASS UNTIL INITIALIZATION, THEN APPLY RETROACTIVELY
        uint stashed = _balanceShares[BalanceShareId.Deposits].processBalanceShare(depositAmount);
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
     * @dev Before execution of any action on the Executor, confirm that base asset transfers do not exceed DAO balance,
     * and then update the balance to account for the transfer.
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

    /**
     * @dev Used in the _beforeExecute hook to check for base asset transfers. Needs to be overridden based on the base
     * asset type. This should return the amount being transferred from the Treasurer in the provided transaction so it
     * can be accounted for in the internal balance state.
     */
    function _checkExecutionBalanceTransfer(
        address target,
        uint256 value,
        bytes calldata data
    ) internal virtual returns (uint256 balanceBeingTransferred);

}