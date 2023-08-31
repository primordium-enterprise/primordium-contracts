// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.4;

import "../Treasurer.sol";
import "contracts/utils/BalanceShares.sol";

abstract contract TreasurerBalanceShares is Treasurer {

    using BalanceShares for BalanceShares.BalanceShare;

    enum BalanceShareId {
        Deposits,
        Revenue
    }

    mapping(BalanceShareId => BalanceShares.BalanceShare) private _balanceShares;

    // The previously measured DAO balance (minus any _stashedBalance), for tracking changes to the balance amount
    uint256 private _lastProcessedBalance;

    // Tracks cumulative balance transfers since the last storage write to _lastProcessedBalance
    uint256 private _balanceTransfers;

    event BalanceShareAdded(
        BalanceShareId indexed id,
        address indexed account,
        uint256 bps,
        uint256 removableAt
    );

    event BalanceShareRemoved(
        BalanceShareId indexed id,
        address indexed account
    );

    event BalanceShareWithdrawal(
        BalanceShareId indexed id,
        address indexed account,
        uint256 amount
    );

    event BalanceShareAccountBpsUpdated(
        BalanceShareId indexed id,
        address indexed account,
        uint256 newAccountBps
    );

    event BalanceShareAccountRemovableAtUpdated(
        BalanceShareId indexed id,
        address indexed account,
        uint256 newRemovableAt
    );

    /**
     * @dev Modifier to stash revenue shares before proceeding with the rest of the function call. Important for many
     * BalanceShare updates to ensure that all unprocessed revenue is stashed before writing any updates to the
     * BalanceShare storage.
     */
    modifier stashRevenueSharesFirst(BalanceShareId id) {
        if (id == BalanceShareId.Revenue) _stashRevenueShares();
        _;
    }

    /**
     * @notice A method to retrieve a human-readable name for each enum value of the BalanceShareId enum.
     * @param id The enum identifier indicating which balance share this applies to.
     * @return name The human-readable name of the specified BalanceShareId.
     */
    function balanceShareName(BalanceShareId id) external pure returns (string memory) {
        if (id == BalanceShareId.Deposits) {
            return "DepositShares";
        } else if (id == BalanceShareId.Revenue) {
            return "RevenueShares";
        }
        // solhint-disable-next-line
        revert();
    }

    /**
     * @notice Helper function for easily viewing the current internal accounting variables.
     * @return stashedBalance The currently stashed balance.
     * @return lastProcessedBalance The treasury balance last time revenue was stashed.
     * @return balanceTransfers A sum of all balance transfers since the last time the revenue was stashed.
     */
    function internalAccounting() external view returns (uint256, uint256, uint256) {
        return (_stashedBalance, _lastProcessedBalance, _balanceTransfers);
    }

    /**
     * @notice A publicly callable function to update the treasury balances, processing any revenue shares and saving
     * these updates to the contract state. This does NOT send revenue shares to the receipient accounts, it simply
     * updates the internal accounting allocate the revenue shares to be withdrawable by the recipients.
     * @return Returns the amount of the base asset that stashed for revenue shares as part of this function call.
     */
    function processRevenueShares() external returns (uint256) {
        return _stashRevenueShares();
    }

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
    ) public virtual onlyTimelock stashRevenueSharesFirst(id) {
        _balanceShares[id].addAccountShares(newAccountShares);
        for (uint256 i = 0; i < newAccountShares.length;) {
            emit BalanceShareAdded(
                id,
                newAccountShares[i].account,
                newAccountShares[i].bps,
                newAccountShares[i].removableAt
            );
            unchecked { i++; }
        }
    }

    /**
     * @notice Removes the provided accounts from the specified balance shares. Only callable by the timelock itself,
     * and only works if past the "removableAt" timestamp for the account.
     * @param id The enum identifier indicating which balance share this applies to.
     * @param accounts An array of accounts to remove from the specified balance share.
     */
    function removeBalanceShares(
        BalanceShareId id,
        address[] calldata accounts
    ) public virtual onlyTimelock stashRevenueSharesFirst(id) {
        _balanceShares[id].removeAccountShares(accounts);
        for (uint256 i = 0; i < accounts.length;) {
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
    function removeBalanceShareSelf(BalanceShareId id) external virtual stashRevenueSharesFirst(id) {
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

    /**
     * @notice Sends any balance share owed to the provided account. Only callable by the account recipient or approved
     * addresses.
     * @param id The enum identifier indicating which balance share this applies to.
     * @param account The account to process the withdrawal for. Any outstanding funds will be sent to this address.
     */
    function processBalanceShareWithdrawal(
        BalanceShareId id,
        address account
    ) external virtual stashRevenueSharesFirst(id) returns (uint256) {
        uint256 withdrawAmount = _balanceShares[id].processAccountWithdrawal(account);
        _transferStashedBaseAsset(account, withdrawAmount); // Subtracts from the stashed balance
        emit BalanceShareWithdrawal(id, account, withdrawAmount);
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
        uint256 currentBalance = super._treasuryBalance();
        uint256 unprocessedRevenue = _getUnprocessedRevenue(currentBalance);
        return _balanceShares[id].predictedAccountBalance(account, unprocessedRevenue);
    }

    /**
     * @notice Retrieve the sum total BPS (basis points) accross all accounts for the specified balance share.
     * @param id The enum identifier indicating which balance share this applies to.
     */
    function balanceShareTotalBps(BalanceShareId id) external view virtual returns (uint256) {
        return _balanceShares[id].totalBps();
    }

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
    ) public virtual onlyTimelock stashRevenueSharesFirst(id) returns (uint256) {
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

    /**
     * @dev Override to retrieve the base asset balance available to the DAO.
     *
     * Calculates any revenue shares that would need to be applied first (but doesn't save these to state in order to
     * save gas)
     */
    function _treasuryBalance() internal view virtual override returns (uint256) {
        uint256 currentBalance = Treasurer._treasuryBalance(); // _baseAssetBalance() - _stashedBalance
        uint256 unprocessedRevenue = _getUnprocessedRevenue(currentBalance);
        if (unprocessedRevenue > 0) {
            currentBalance -= _balanceShares[BalanceShareId.Revenue].calculateBalanceToAddToShares(unprocessedRevenue);
        }
        return currentBalance;
    }

    function _getUnprocessedRevenue(uint256 treasuryBalance_) internal view virtual returns (uint256) {
        /**
         * treasuryBalance_ = _baseAssetBalance() - _stashedBalance
         * unprocessedRevenue = treasuryBalance_ - (_lastProcessedBalance - _balanceTransfers)
         */
        uint256 prevBalance = _lastProcessedBalance;
        uint256 balanceTransfers = _balanceTransfers;
        // Double negative needs to become positive
        return balanceTransfers > prevBalance ?
            treasuryBalance_ + (balanceTransfers - prevBalance) :
            treasuryBalance_ - (prevBalance - balanceTransfers);
    }

    /**
     * @dev Update function that balances the treasury based on any revenue changes that occurred since the last update.
     *
     * Saves these changes to the _lastProcessedBalance and _stashedBalance storage state, return the amount stashed.
     *
     * Calls BalanceShares.processBalance on the revenue shares to track any balance remainders as well.
     */
    function _stashRevenueShares() internal virtual returns (uint256 stashed) {
        uint256 currentBalance = Treasurer._treasuryBalance(); // _baseAssetBalance() - _stashedBalance
        uint256 unprocessedRevenue = _getUnprocessedRevenue(currentBalance);
        if (unprocessedRevenue > 0) {
            stashed = _balanceShares[BalanceShareId.Revenue].processBalance(unprocessedRevenue);
            _stashBaseAsset(stashed);
            currentBalance -= stashed;
             // Set the _lastProcessedBalance to the current treasury balance
            _lastProcessedBalance = currentBalance;
            // Zero out the value of _balanceTransfers
            _balanceTransfers = 0;
        }
        return stashed;
    }

    function _processDepositShares(uint256 depositAmount) internal virtual {
        uint256 stashed = _balanceShares[BalanceShareId.Deposits].processBalance(depositAmount);
        if (stashed > 0) {
            _lastProcessedBalance += depositAmount - stashed;
            _stashBaseAsset(stashed);
        }
    }

    /// @dev Override to implement balance updates on the treasury for deposit shares
    function _registerDeposit(
        uint256 depositAmount,
        IVotesProvisioner.ProvisionMode provisionMode
    ) internal virtual override {
        super._registerDeposit(depositAmount, provisionMode);
        if (provisionMode > IVotesProvisioner.ProvisionMode.Founding) {
            _processDepositShares(depositAmount);
        }
    }

    function _governanceInitialized(uint256 baseAssetDeposits) internal virtual override {
        super._governanceInitialized(baseAssetDeposits);
        _processDepositShares(baseAssetDeposits);
    }

    /**
     * @dev Override to implement internal accounting to track all cumulative balance transfers since the last time
     * revenue was stashed.
     */
    function _processBaseAssetTransfer(uint256 amount) internal virtual override {
        _balanceTransfers += amount;
    }

    /**
     * @dev Override to implement internal accounting to track all cumulative reverse balance transfers since the last
     * time revenue was stashed.
     *
     * NOTE: If balance transfers risks underflow, then it will instead add to the _lastProcessedBalance (serving the
     * same desired effect)
     */
    function _processReverseBaseAssetTransfer(uint256 amount) internal virtual override {
        uint256 currentBalanceTransfers = _balanceTransfers;
        if (currentBalanceTransfers >= amount) {
            _balanceTransfers -= amount;
        } else {
            _lastProcessedBalance += amount;
        }
    }

    /**
     * @dev Helper method to decrease the BPS share for an account.
     */
    function _decreaseBalanceShareAccountBps(
        BalanceShareId id,
        address account,
        uint256 decreaseByBps
    ) internal virtual stashRevenueSharesFirst(id) returns (uint256) {
        uint256 newAccountBps = _balanceShares[id].decreaseAccountBps(account, decreaseByBps);
        emit BalanceShareAccountBpsUpdated(id, account, newAccountBps);
        return newAccountBps;
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

}