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
     * these updates to the contract state. This does NOT send revenue shares to the receipient accounts, it simply
     * updates the internal accounting allocate the revenue shares to be withdrawable by the recipients.
     */
    function processRevenueShares() external returns (uint256) {
        return _processRevenueShares();
    }

    /**
     * @dev Update function that balances the treasury based on any revenue changes that occurred since the last update.
     *
     * Saves these changes to the _balance and _stashedBalance storage state.
     *
     * Calls BalanceShares.processBalance on the revenue shares to track any balance remainders as well.
     */
    function _processRevenueShares() internal virtual returns (uint256) {
        uint currentBalance = _currentTreasuryBalance();
        uint prevBalance = _balance;
        // If revenue occurred, apply revenue shares and update the balances
        if (currentBalance > prevBalance) {
            uint increasedBy = currentBalance - prevBalance;
            // Use "processBalance" function to account for the remainder
            uint stashed = _balanceShares[BalanceShareId.Revenue].processBalance(increasedBy);
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
        uint stashed = _balanceShares[BalanceShareId.Deposits].processBalance(depositAmount);
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


    event BalanceShareAdded(
        BalanceShareId indexed balanceShareId,
        address indexed account,
        uint256 bps,
        uint256 removableAt
    );

    /**
     * @notice Adds the specified balance shares to the treasury. Only callable by the timelock itself.
     * @param balanceShareId The enum identifier for which balance share this applies to.
     * @param newAccountShares An array of BalanceShares.NewAccountShare structs defining the account shares to add to
     * the specified balance share. Each struct item should contain the following properties:
     * - address account The address of the new account share recipient
     * - uint256 bps The basis points share for this account
     * - uint256 removeableAt A timestamp (in UTC seconds) for when this account share will be removeable/decreasable
     * - address[] approvedAddressesForWithdrawal An array of addresses approved to initiate a withdrawal to the account
     * recipient. If address(0) is approved, then any address can initiate a withdrawal to the account recipient.
     */
    function addBalanceShares(
        BalanceShareId balanceShareId,
        BalanceShares.NewAccountShare[] calldata newAccountShares
    ) public virtual onlyTimelock {
        if (balanceShareId == BalanceShareId.Revenue) _processRevenueShares();
        _balanceShares[balanceShareId].addAccountShares(newAccountShares);
        for (uint i = 0; i < newAccountShares.length;) {
            emit BalanceShareAdded(
                balanceShareId,
                newAccountShares[i].account,
                newAccountShares[i].bps,
                newAccountShares[i].removableAt
            );
            unchecked { i++; }
        }
    }

    event BalanceShareRemoved(
        BalanceShareId indexed balanceShareId,
        address indexed account
    );

    /**
     * @notice Removes the provided accounts from the specified balance shares.
     * @param balanceShareId The enum identifier for which balance share this applies to.
     * @param accounts An array of accounts to remove from the specified balance share.
     */
    function removeBalanceShares(
        BalanceShareId balanceShareId,
        address[] calldata accounts
    ) public virtual onlyTimelock {
        if (balanceShareId == BalanceShareId.Revenue) _processRevenueShares();
        _balanceShares[balanceShareId].removeAccountShares(accounts);
        for (uint i = 0; i < accounts.length;) {
            emit BalanceShareRemoved(
                balanceShareId,
                accounts[i]
            );
            unchecked { i++; }
        }
    }

    /**
     * @notice This function removes the specified balance share owned by msg.sender. NOTE: This does not process the
     * balance withdrawal for msg.sender.
     * @param balanceShareId The enum identifier for which balance share this applies to.
     */
    function removeBalanceShareSelf(BalanceShareId balanceShareId) external virtual {
        if (balanceShareId == BalanceShareId.Revenue) _processRevenueShares();
        _balanceShares[balanceShareId].removeAccountShareSelf();
        emit BalanceShareRemoved(
            balanceShareId,
            msg.sender
        );
    }

    /**
     * @notice A balance share recipient can approve addresses to initiate withdrawals to the recipient.
     * @param balanceShareId The enum identifier for which balance share this applies to.
     * @param approvedAddresses An array of addresses to approve.
     */
    function approveAddressesForBalanceShareWithdrawal(
        BalanceShareId balanceShareId,
        address[] calldata approvedAddresses
    ) external virtual {
        _balanceShares[balanceShareId].approveAddressesForWithdrawal(
            msg.sender,
            approvedAddresses
        );
    }

    /**
     * @notice A balance share recipient can unapprove addresses for initiating withdrawals.
     * @param balanceShareId The enum identifier for which balance share this applies to.
     * @param unapprovedAddresses An array of addresses to unapprove.
     */
    function unapproveAddressesForBalanceShareWithdrawal(
        BalanceShareId balanceShareId,
        address[] calldata unapprovedAddresses
    ) external virtual {
        _balanceShares[balanceShareId].unapproveAddressesForWithdrawal(
            msg.sender,
            unapprovedAddresses
        );
    }

    /**
     * @notice View function to check whether an address is approved for withdrawals for a given account share.
     * @param balanceShareId The enum identifier for which balance share this applies to.
     * @param account The balance share account recipient.
     * @param addressToCheck The address to check for approval
     * @return Returns a bool indicating whether or not the "addressToCheck" is approved to withdraw to the given
     * "account."
     */
    function isAddressApprovedForBalanceShareWithdrawal(
        BalanceShareId balanceShareId,
        address account,
        address addressToCheck
    ) external view virtual returns (bool) {
        return _balanceShares[balanceShareId].isAddressApprovedForWithdrawal(account, addressToCheck);
    }

    event BalanceShareWithdrawal(
        address indexed account,
        uint256 amount
    );

    /**
     * @notice Sends any balance share owed to the provided account. Only callable by the account recipient or approved
     * addresses.
     * @param balanceShareId The enum identifier for which balance share this applies to.
     * @param account The account to process the
     */
    function processBalanceShareWithdrawal(
        BalanceShareId balanceShareId,
        address account
    ) external virtual returns (uint256) {
        if (balanceShareId == BalanceShareId.Revenue) _processRevenueShares();
        uint256 withdrawAmount = _balanceShares[balanceShareId].processAccountWithdrawal(account);
        _stashedBalance -= withdrawAmount;
        _transferBaseAsset(account, withdrawAmount);
        return withdrawAmount;
    }

}