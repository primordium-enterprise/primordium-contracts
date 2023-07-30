// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

library BalanceShares {

    uint constant MAX_BPS = 10_000; // Max total BPS (1 basis point == 0.01%, which is 1 / 10_000)
    uint40 constant MAX_INDEX = type(uint40).max;
    uint256 constant MAX_CHECK_BALANCE_AMOUNT = type(uint240).max;

    struct BalanceShare {
        BalanceCheck[] _balanceChecks; // New balanceCheck pushed every time totalBps changes, or when balance overflow occurs, max length is type(uint40).max
        mapping(address => AccountShare) _accounts;
        mapping(address => mapping(address => bool)) _accountWithdrawalApprovals;
    }

    struct BalanceCheck {
        uint16 totalBps; // Tracks the totalBps among all balance shares for this checkpoint
        uint240 balance; // The balance sum to be shared among receiving accounts for this checkpoint, only increases
    }

    struct AccountShare {
        uint16 bps; // The basis points share of this account
        uint40 createdAt; // A timestamp indicating when this account share was created
        uint40 removableAt; // A timestamp (in UTC seconds) at which the revenue share can be removed by the DAO
        uint40 lastWithdrawnAt; // A timestamp (in UTC seconds) at which the revenue share was last withdrawn
        uint40 startIndex; // Balance index at which this account share starts participating
        uint40 endIndex; // Where this account finished participating, or type(uint40).max when still active
        uint40 lastBalanceCheckIndex; // The last balanceCheck index that was withdrawn from
        uint256 lastBalancePulled; // The balance of balanceChecks[lastBalanceCheckIndex] when it was last withdrawn
    }

    struct NewAccountShare {
        address account;
        uint bps;
        uint removableAt;
        address[] approvedAddressesForWithdrawal;
    }

    /**
     * @dev Adds the provided account shares to the total balance shares being tracked.
     * For accounts that cannot claim their withdrawals on their own (because they don't have functions to do so),
     * it is recommended to provide [address(0)] for the approvedAccountsForWithdrawal so that any address can claim
     * the withdrawal proceeds on behalf of the account.
     */
    function addAccountShares(
        BalanceShare storage self,
        NewAccountShare[] memory newAccountShares
    ) internal {
        require(newAccountShares.length > 0);

        // Initialize the lastBalanceCheck
        BalanceCheck memory lastBalanceCheck = BalanceCheck(0, 0);

        // Get startIndex of the nextBalanceCheck (assumed to be equal to length since we are pushing a new balanceCheck)
        uint startIndex = self._balanceChecks.length;

        // If length is greater than zero, then copy the last array element to the nextBalanceCheck
        if (startIndex > 0) {
            lastBalanceCheck = self._balanceChecks[startIndex - 1];
            // If the balance of the last element is zero, then we plan to just overwrite this checkpoint
            if (lastBalanceCheck.balance == 0) {
                startIndex -= 1;
            }
        } else {
            // If length not greater than zero, initialize the first element
            self._balanceChecks.push(lastBalanceCheck);
        }

        // Cache as uint40 for loop below, SafeCast ensures array length is no larger than type(uint40).max
        uint40 startIndexUint40 = SafeCast.toUint40(startIndex);

        // Loop through accounts and track BPS changes
        uint addToTotalBps;
        uint40 currentTimestamp = uint40(block.timestamp); // Cache timestamp in memory to save gas in loop

        for (uint i = 0; i < newAccountShares.length;) {
            NewAccountShare memory newAccountShare = newAccountShares[i];

            // Check that the account has zeroed out previous balances (on the off chance that it existed previously)
            require(_accountHasFinishedWithdrawals(self._accounts[newAccountShare.account]));

            addToTotalBps += newAccountShare.bps; // We don't verify the BPS amount here, because total will be verified below
            // Initialize the new AccountShare
            self._accounts[newAccountShare.account] = AccountShare({
                bps: SafeCast.toUint16(newAccountShare.bps),
                createdAt: currentTimestamp,
                removableAt: SafeCast.toUint40(newAccountShare.removableAt),
                lastWithdrawnAt: currentTimestamp,
                startIndex: startIndexUint40,
                endIndex: MAX_INDEX,
                lastBalanceCheckIndex: startIndexUint40,
                lastBalancePulled: 0
            });
            // Initialize the approvedForWithdrawal addresses
            approveAddressesForWithdrawal(
                self,
                newAccountShare.account,
                newAccountShare.approvedAddressesForWithdrawal
            );
            unchecked {
                i++;
            }
        }

        // Calculate the new totalBps, and make sure it is valid
        uint newTotalBps = lastBalanceCheck.totalBps + addToTotalBps;
        require(newTotalBps <= MAX_BPS);

        // Update the totalBps
        _updateTotalBps(self, lastBalanceCheck.balance, startIndex, uint16(newTotalBps));

    }

    /**
     * @dev Removes the specified accounts from receiving further shares. Does not process withdrawals. The receivers
     * will still have access to withdraw their balances that were accumulated prior to removal.
     *
     * Requires that the block.timestamp is greater than the account's "removeableAt" parameter, or else throws an error.
     */
    function removeAccountShares(
        BalanceShare storage self,
        address[] memory accounts
    ) internal {
        _removeAccountShares(self, accounts, false);
    }

    /**
     * @dev Same as the {removeAccountShares} function call, but skips checking the "removeableAt" parameter.
     */
    function removeAccountSharesSkippingRemoveableAtCheck(
        BalanceShare storage self,
        address[] memory accounts
    ) internal {
        _removeAccountShares(self, accounts, true);
    }

    function _removeAccountShares(
        BalanceShare storage self,
        address[] memory accounts,
        bool skipRemoveableAtCheck
    ) private {
        uint currentTimestamp = block.timestamp;
        uint subFromTotalBps;
        uint latestBalanceCheckIndex = self._balanceChecks.length - 1;
        for (uint i = 0; i < accounts.length;) {
            AccountShare storage accountShare = self._accounts[accounts[i]];
            uint bps = accountShare.bps;
            uint endIndex = accountShare.endIndex;
            uint removeableAt = accountShare.removableAt;
            // The account share must be active to be removed
            require(endIndex == MAX_INDEX);
            // The current timestamp must be greater than the removeableAt timestamp (unless explicitly skipped)
            require(skipRemoveableAtCheck || currentTimestamp >= removeableAt);

            // Set the bps to 0, and the endIndex to be the current balance share index
            accountShare.bps = 0;
            accountShare.endIndex = uint40(latestBalanceCheckIndex);

            unchecked {
                subFromTotalBps += bps; // Can be unchecked, bps was checked when the account share was added
                i++;
            }
        }

        BalanceCheck memory latestBalanceCheck = self._balanceChecks[latestBalanceCheckIndex];

        uint newTotalBps = latestBalanceCheck.totalBps - subFromTotalBps;

        // Update the totalBps
        _updateTotalBps(self, latestBalanceCheck.balance, latestBalanceCheckIndex, uint16(newTotalBps));

    }

    /**
     * @dev Method to add to the total pool of balance available to the account shares, at the rate of:
     * balanceIncreasedBy * totalBps / 10_000
     * @param balanceIncreasedBy A uint256 representing how much the core balance increased by, which will be multiplied
     * by the totalBps for all active balance shares to be made available to those accounts.
     * @return balanceAddedToShares Returns the amount added to the balance shares, which should be accounted for in the
     * host contract.
     */
    function processBalanceShares(
        BalanceShare storage self,
        uint256 balanceIncreasedBy
    ) internal returns (uint256 balanceAddedToShares) {
        uint length = self._balanceChecks.length;
        // Only continue if the length is greater than zero, otherwise returns zero by default
        if (length > 0) {
            BalanceCheck storage latestBalanceCheck = self._balanceChecks[length - 1];
            uint totalBps = latestBalanceCheck.totalBps;
            balanceAddedToShares = _calculateBalanceShare(balanceIncreasedBy, totalBps);
            _addBalance(self, latestBalanceCheck, balanceAddedToShares);
        }
    }

    function _calculateBalanceShare(
        uint256 balanceIncreasedBy,
        uint256 totalBps
    ) private pure returns (uint256) {
        // Only run the mulDiv if the totalBps is greater than zero
        return totalBps > 0 ?
            Math.mulDiv(balanceIncreasedBy, totalBps, MAX_BPS) :
            0;
    }

    /**
     * @dev Private function, adds the provided balance amount to the shared balances.
     */
    function _addBalance(
        BalanceShare storage self,
        BalanceCheck storage latestBalanceCheck,
        uint256 amount
    ) private {
        if (amount > 0) {
            // Unchecked because manual checks ensure no overflow/underflow
            unchecked {
                // Start with a reference to the current balance
                uint currentBalance = latestBalanceCheck.balance;
                // Loop until break
                while (true) {
                    // Can only increase current balanceCheck up to the MAX_CHECK_BALANCE_AMOUNT
                    uint balanceIncrease = Math.min(amount, MAX_CHECK_BALANCE_AMOUNT - currentBalance);
                    latestBalanceCheck.balance = uint240(currentBalance + balanceIncrease);
                    amount -= balanceIncrease;
                    // If there is still more balance remaining, push a new balanceCheck and zero out the currentBalance
                    if (amount > 0) {
                        self._balanceChecks.push(BalanceCheck(latestBalanceCheck.totalBps, 0));
                        latestBalanceCheck = self._balanceChecks[self._balanceChecks.length - 1];
                        currentBalance = 0;
                    } else {
                        break; // Can complete once amount remaining is zero
                    }
                }
            }
        }
    }

    /**
     * @dev Processes an account withdrawal, calculating the balance amount that should be paid out to the account. As a
     * result of this function, the balance amount to be paid out is marked as withdrawn for this account. The host
     * contract is responsible for ensuring this balance is paid out to the account as part of the transaction.
     *
     * @param account The address of the withdrawing account.
     * @return balanceToBePaid This is the balance that is marked as paid out for the account. The host contract should
     * pay this balance to the account as part of the withdrawal transaction.
     */
    function processAccountWithdrawal(
        BalanceShare storage self,
        address account
    ) internal returns (uint256) {
        return _accountBalance(
            self,
            account,
            true // Save to storage, as this assumes the balance is being paid out
        );
    }

    function accountBalance(
        BalanceShare storage self,
        address account
    ) internal returns (uint256) {
        return _accountBalance(
            self,
            account,
            false // Don't save to storage
        );
    }

    function _accountBalance(
        BalanceShare storage self,
        address account,
        bool updateAccountShare
    ) private returns(uint256 balanceToBePaid) {
        AccountShare storage accountShare = self._accounts[account];
        (
            uint bps,
            uint createdAt,
            uint endIndex,
            uint lastBalanceCheckIndex,
            uint lastBalancePulled
        ) = (
            accountShare.bps,
            accountShare.createdAt,
            accountShare.endIndex,
            accountShare.lastBalanceCheckIndex,
            accountShare.lastBalancePulled
        );

        // If account is not active or is already finished with withdrawals, return 0
        if (_accountHasFinishedWithdrawals(createdAt, lastBalanceCheckIndex, endIndex)) {
            return balanceToBePaid;
        }

        uint latestBalanceCheckIndex = self._balanceChecks.length - 1;

        // Process each balanceCheck while in range of the endIndex, summing the total balance to be paid
        while (lastBalanceCheckIndex <= endIndex) {
            BalanceCheck memory balanceCheck = self._balanceChecks[lastBalanceCheckIndex];
            uint diff = balanceCheck.balance - lastBalancePulled;
            if (diff > 0 && balanceCheck.totalBps > 0) {
                // For each check, add ( balanceCheck.balance - lastBalancePulled ) * ( accountBps / balanceCheck.totalBps )
                balanceToBePaid += Math.mulDiv(diff, bps, balanceCheck.totalBps);
            }
            // Do not increment past the end of the balanceChecks array
            if (lastBalanceCheckIndex == latestBalanceCheckIndex) {
                // Track this balance to save to the account's storage as the lastPulledBalance
                unchecked {
                    lastBalancePulled = balanceCheck.balance;
                }
                break;
            }
            /**
             * @dev Notice that this increments the lastBalanceCheckIndex PAST the endIndex for an account that has had
             * their balance share removed at some point.
             *
             * This is the desired behavior. See the private {_accountHasFinishedWithdrawals} function. This considers an
             * account to be finished with withdrawals once the lastBalanceCheckIndex is greater than the endIndex.
             */
            unchecked {
                lastBalanceCheckIndex += 1;
                lastBalancePulled = 0;
            }
        }

        // If flagged as such, save the account updates to storage
        if (updateAccountShare) {
            accountShare.lastBalanceCheckIndex = uint40(lastBalanceCheckIndex);
            accountShare.lastBalancePulled = lastBalancePulled;
        }

        return balanceToBePaid;

    }

    function approveAddressesForWithdrawal(
        BalanceShare storage self,
        address account,
        address[] memory approvedAddresses
    ) internal {
        for (uint i = 0; i < approvedAddresses.length;) {
            self._accountWithdrawalApprovals[account][approvedAddresses[i]] = true;
            unchecked {
                i++;
            }
        }
    }

    function unapproveAddressesForWithdrawal(
        BalanceShare storage self,
        address account,
        address[] memory unapprovedAddresses
    ) internal {
        for (uint i = 0; i < unapprovedAddresses.length;) {
            self._accountWithdrawalApprovals[account][unapprovedAddresses[i]] = false;
            unchecked {
                i++;
            }
        }
    }

    function isAddressApprovedForWithdrawal(
        BalanceShare storage self,
        address account,
        address address_
    ) internal view returns (bool) {
        return self._accountWithdrawalApprovals[account][address_];
    }

    /**
     * @dev Returns the following details (in order) for the specified account:
     * - bps
     * - createdAt
     * - removeableAt
     * - lastWithdrawnAt
     */
    function accountDetails(
        BalanceShare storage self,
        address account
    ) internal view returns (uint256, uint256, uint256, uint256) {
        AccountShare storage accountShare = self._accounts[account];
        return (
            accountShare.bps,
            accountShare.createdAt,
            accountShare.removableAt,
            accountShare.lastWithdrawnAt
        );
    }

    /**
     * @dev Helper method for updating the totalBps for a BalanceShare. Checks if it needs to push a new BalanceCheck
     * item to the array, or if it can just update the totalBps for the latest item (if the balance is already zero).
     */
    function _updateTotalBps(
        BalanceShare storage self,
        uint256 latestBalance,
        uint256 latestBalanceCheckIndex,
        uint16 newTotalBps
    ) private {
        // If the latestBalance is greater than 0, then push a new item, otherwise just update the current item
        if (latestBalance > 0) {
            self._balanceChecks.push(BalanceCheck(newTotalBps, 0));
        } else {
            self._balanceChecks[latestBalanceCheckIndex].totalBps = newTotalBps;
        }
    }

    /**
     * @dev An account is considered to be finished with withdrawals when the account's "lastBalanceCheckIndex" is
     * greater than the account's "endIndex"
     *
     * Returns true if the account has not been initialized with any shares yet
     */
    function _accountHasFinishedWithdrawals(
        AccountShare storage accountShare
    ) private view returns (bool) {
        (uint createdAt, uint lastBalanceCheckIndex, uint endIndex) = (
            accountShare.createdAt,
            accountShare.lastBalanceCheckIndex,
            accountShare.endIndex
        );
        return _accountHasFinishedWithdrawals(createdAt, lastBalanceCheckIndex, endIndex);
    }

    /**
     * @dev Overload for checking if these values are already loaded into memory (to save gas).
     */
    function _accountHasFinishedWithdrawals(
        uint createdAt,
        uint lastBalanceCheckIndex,
        uint endIndex
    ) private pure returns (bool) {
        return createdAt == 0 || lastBalanceCheckIndex > endIndex;
    }

}