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
    function stashRevenueShares() external returns (uint256) {
        return _stashRevenueShares();
    }

    /**
     * @dev Update function that balances the treasury based on any revenue changes that occurred since the last update.
     *
     * Saves these changes to the _balance and _stashedBalance storage state.
     *
     * Calls BalanceShares.processBalance on the revenue shares to track any balance remainders as well.
     */
    function _stashRevenueShares() internal virtual returns (uint256) {
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
        super._processWithdrawal(receiver, withdrawAmount);
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
        BalanceShareId indexed id,
        address indexed account,
        uint256 bps,
        uint256 removableAt
    );

    /**
     * @notice Adds the specified balance shares to the treasury. Only callable by the timelock itself.
     * @param id The enum identifier indicating which balance share this applies to.
     * @param newAccountShares An array of BalanceShares.NewAccountShare structs defining the account shares to add to
     * the specified balance share. Each struct item should contain the following properties:
     * - address account The address of the new account share recipient
     * - uint256 bps The basis points share for this account
     * - uint256 removeableAt A timestamp (in UTC seconds) for when this account share will be removeable/decreasable
     * - address[] approvedAddressesForWithdrawal An array of addresses approved to initiate a withdrawal to the account
     * recipient. If address(0) is approved, then any address can initiate a withdrawal to the account recipient.
     */
    function addBalanceShares(
        BalanceShareId id,
        BalanceShares.NewAccountShare[] calldata newAccountShares
    ) public virtual onlyTimelock {
        if (id == BalanceShareId.Revenue) _stashRevenueShares();
        _balanceShares[id].addAccountShares(newAccountShares);
        for (uint i = 0; i < newAccountShares.length;) {
            emit BalanceShareAdded(
                id,
                newAccountShares[i].account,
                newAccountShares[i].bps,
                newAccountShares[i].removableAt
            );
            unchecked { i++; }
        }
    }

    event BalanceShareRemoved(
        BalanceShareId indexed id,
        address indexed account
    );

    /**
     * @notice Removes the provided accounts from the specified balance shares. Only callable by the timelock itself, and
     * only works if past the "removableAt" timestamp for the account.
     * @param id The enum identifier indicating which balance share this applies to.
     * @param accounts An array of accounts to remove from the specified balance share.
     */
    function removeBalanceShares(
        BalanceShareId id,
        address[] calldata accounts
    ) public virtual onlyTimelock {
        if (id == BalanceShareId.Revenue) _stashRevenueShares();
        _balanceShares[id].removeAccountShares(accounts);
        for (uint i = 0; i < accounts.length;) {
            emit BalanceShareRemoved(
                id,
                accounts[i]
            );
            unchecked { i++; }
        }
    }

    /**
     * @notice This function removes the specified balance share owned by msg.sender. NOTE: This does not process the
     * balance withdrawal for msg.sender.
     * @param id The enum identifier indicating which balance share this applies to.
     */
    function removeBalanceShareSelf(BalanceShareId id) external virtual {
        if (id == BalanceShareId.Revenue) _stashRevenueShares();
        _balanceShares[id].removeAccountShareSelf();
        emit BalanceShareRemoved(
            id,
            msg.sender
        );
    }

    /**
     * @notice A balance share recipient can approve addresses to initiate withdrawals to the recipient.
     * @param id The enum identifier indicating which balance share this applies to.
     * @param approvedAddresses An array of addresses to approve.
     */
    function approveAddressesForBalanceShareWithdrawal(
        BalanceShareId id,
        address[] calldata approvedAddresses
    ) external virtual {
        _balanceShares[id].approveAddressesForWithdrawal(
            msg.sender,
            approvedAddresses
        );
    }

    /**
     * @notice A balance share recipient can unapprove addresses for initiating withdrawals.
     * @param id The enum identifier indicating which balance share this applies to.
     * @param unapprovedAddresses An array of addresses to unapprove.
     */
    function unapproveAddressesForBalanceShareWithdrawal(
        BalanceShareId id,
        address[] calldata unapprovedAddresses
    ) external virtual {
        _balanceShares[id].unapproveAddressesForWithdrawal(
            msg.sender,
            unapprovedAddresses
        );
    }

    /**
     * @notice View function to check whether an address is approved for withdrawals for a given account share.
     * @param id The enum identifier indicating which balance share this applies to.
     * @param account The balance share account recipient.
     * @param addressToCheck The address to check for approval
     * @return Returns a bool indicating whether or not the "addressToCheck" is approved to withdraw to the given
     * "account."
     */
    function isAddressApprovedForBalanceShareWithdrawal(
        BalanceShareId id,
        address account,
        address addressToCheck
    ) external view virtual returns (bool) {
        return _balanceShares[id].isAddressApprovedForWithdrawal(account, addressToCheck);
    }

    event BalanceShareWithdrawal(
        BalanceShareId indexed id,
        address indexed account,
        uint256 amount
    );

    /**
     * @notice Sends any balance share owed to the provided account. Only callable by the account recipient or approved
     * addresses.
     * @param id The enum identifier indicating which balance share this applies to.
     * @param account The account to process the withdrawal for. Any outstanding funds will be sent to this address.
     */
    function processBalanceShareWithdrawal(
        BalanceShareId id,
        address account
    ) external virtual returns (uint256) {
        if (id == BalanceShareId.Revenue) _stashRevenueShares();
        uint256 withdrawAmount = _balanceShares[id].processAccountWithdrawal(account);
        _stashedBalance -= withdrawAmount;
        _transferBaseAsset(account, withdrawAmount);
        return withdrawAmount;
    }

    /**
     * @notice Retrieve the account details for the specified balance share and account address.
     * @param id The enum identifier indicating which balance share this applies to.
     * @param account The account address to retrieve the details for.
     * @return bps The account basis points share.
     * @return createdAt The block timestamp of when the balance share was added.
     * @return removableAt The block timestamp of when the balance share is removeable/decreasable.
     * @return lastWithdrawnAt The block timestamp of when the balance share was last withdrawn.
     */
    function balanceShareAccountDetails(
        BalanceShareId id,
        address account
    ) external view virtual returns (uint256, uint256, uint256, uint256) {
        return _balanceShares[id].accountDetails(account);
    }

    /**
     * @notice Retrieve the balance available for withdrawal for an account.
     * @param id The enum identifier indicating which balance share this applies to.
     * @param account The account address.
     */
    function balanceShareAccountBalance(
        BalanceShareId id,
        address account
    ) external view virtual returns (uint256) {
        uint currentBalance = _currentTreasuryBalance();
        uint prevBalance = _balance;
        uint balanceIncreasedBy = currentBalance > prevBalance ? currentBalance - prevBalance : 0;
        return _balanceShares[id].predictedAccountBalance(account, balanceIncreasedBy);
    }

    /**
     * @notice Retrieve the sum total BPS (basis points) accross all accounts for the specified balance share.
     * @param id The enum identifier indicating which balance share this applies to.
     */
    function balanceShareTotalBps(BalanceShareId id) external view virtual returns (uint256) {
        return _balanceShares[id].totalBps();
    }

    event BalanceShareAccountBpsUpdated(
        BalanceShareId indexed id,
        address indexed account,
        uint256 newAccountBps
    );

    /**
     * @notice Increases the BPS share for an account on the specified balance share. Only callable by the timelock
     * itself.
     * @param id The enum identifier indicating which balance share this applies to.
     * @param account The account address.
     * @param increaseByBps The amount of BPS to increase the share by (the new account bps will be the previous account
     * bps with the "increaseByBps" added to it).
     * @return newAccountBps Returns the new account bps.
     */
    function increaseBalanceShareAccountBps(
        BalanceShareId id,
        address account,
        uint256 increaseByBps
    ) public virtual onlyTimelock returns (uint256) {
        if (id == BalanceShareId.Revenue) _stashRevenueShares();
        uint256 newAccountBps = _balanceShares[id].increaseAccountBps(account, increaseByBps);
        emit BalanceShareAccountBpsUpdated(id, account, newAccountBps);
        return newAccountBps;
    }

    /**
     * @notice Decreases the BPS share for an account on the specified balance share. Only callable by the timelock
     * itself, and only works if past the "removableAt" timestamp for the account.
     * @param id The enum identifier indicating which balance share this applies to.
     * @param account The account address.
     * @param decreaseByBps The amount of BPS to decrease the share by (the new account bps will be the previous account
     * bps with the "decreaseByBps" subtracted from it).
     * @return newAccountBps Returns the new account bps.
     */
    function decreaseBalanceShareAccountBps(
        BalanceShareId id,
        address account,
        uint256 decreaseByBps
    ) public virtual onlyTimelock returns (uint256) {
        return _decreaseBalanceShareAccountBps(id, account, decreaseByBps);
    }

    /**
     * @notice Decreases the BPS share for msg.sender on the specified balance share.
     * @param id The enum identifier indicating which balance share this applies to.
     * @param decreaseByBps The amount of BPS to decrease the share by (the new account bps will be the previous account
     * bps with the "decreaseByBps" subtracted from it).
     * @return newAccountBps Returns the new account bps.
     */
    function decreaseBalanceShareAccountBpsSelf(
        BalanceShareId id,
        uint256 decreaseByBps
    ) external virtual returns (uint256) {
        return _decreaseBalanceShareAccountBps(id, msg.sender, decreaseByBps);
    }

    /**
     * @dev Helper method to decrease the BPS share for an account.
     */
    function _decreaseBalanceShareAccountBps(
        BalanceShareId id,
        address account,
        uint256 decreaseByBps
    ) internal virtual returns (uint256) {
        if (id == BalanceShareId.Revenue) _stashRevenueShares();
        uint256 newAccountBps = _balanceShares[id].decreaseAccountBps(account, decreaseByBps);
        emit BalanceShareAccountBpsUpdated(id, account, newAccountBps);
        return newAccountBps;
    }

    event BalanceShareAccountRemovableAtUpdated(
        BalanceShareId indexed id,
        address indexed account,
        uint256 newRemovableAt
    );

    /**
     * @notice Increase the "removableAt" timestamp on the account for the specified balance share. Only callable by the
     * timelock, and only works if past the current "removableAt" timestamp for the account.
     * @param id The enum identifier indicating which balance share this applies to.
     * @param account The account address.
     * @param newRemovableAt The new timestamp to set the removableAt to for the account.
     */
    function increaseBalanceShareAccountRemovableAt(
        BalanceShareId id,
        address account,
        uint256 newRemovableAt
    ) public virtual onlyTimelock {
        _updateBalanceShareAccountRemovableAt(id, account, newRemovableAt);
    }

    /**
     * @notice Decrease the "removableAt" timestamp on the msg.sender's account for the specified balance share.
     * @param id The enum identifier indicating which balance share this applies to.
     * @param newRemovableAt The new timestamp to set the removableAt to for the account
     */
    function decreaseBalanceShareAccountRemovableAtSelf(
        BalanceShareId id,
        uint256 newRemovableAt
    ) external virtual {
        _updateBalanceShareAccountRemovableAt(id, msg.sender, newRemovableAt);
    }

    /**
     * @dev Internal method to update the balance share account's "removableAt" timestamp.
     */
    function _updateBalanceShareAccountRemovableAt(
        BalanceShareId id,
        address account,
        uint256 newRemovableAt
    ) internal virtual {
        _balanceShares[id].updateAccountRemovableAt(account, newRemovableAt);
        emit BalanceShareAccountRemovableAtUpdated(id, account, newRemovableAt);
    }

    /**
     * @notice Returns whether or not the specified account has finished it's withdrawals from it's balance share.
     * @param id The enum identifier indicating which balance share this applies to.
     * @param account The address of the account to check.
     * @return hasFinishedWithdrawals A bool that is true if the account has completed it's full withdrawals, or false
     * otherwise (also returns true if the account has not been initialized, meaning it has 0 withdrawals to process).
     */
    function balanceShareAccountHasFinishedWithdrawals(
        BalanceShareId id,
        address account
    ) external virtual returns (bool) {
        return _balanceShares[id].accountHasFinishedWithdrawals(account);
    }
}