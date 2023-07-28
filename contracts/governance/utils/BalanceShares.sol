// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";

uint constant MAX_BPS = 10_000; // Max total BPS (1 basis point == 0.01%, which is 1 / 10_000)
uint40 constant MAX_INDEX = type(uint40).max;

library BalanceShares {

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
        uint40 lastBalanceIndex; // The last balanceCheck index that was withdrawn from
        uint256 lastBalance; // The balance of balanceChecks[lastBalanceIndex] when it was last withdrawn
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
            require(_accountHasFinishedWithdrawals(self, newAccountShare.account));

            addToTotalBps += newAccountShare.bps; // We don't verify the BPS amount here, because total will be verified below
            // Initialize the new AccountShare
            self._accounts[newAccountShare.account] = AccountShare({
                bps: SafeCast.toUint16(newAccountShare.bps),
                createdAt: currentTimestamp,
                removableAt: SafeCast.toUint40(newAccountShare.removableAt),
                lastWithdrawnAt: currentTimestamp,
                startIndex: startIndexUint40,
                endIndex: MAX_INDEX,
                lastBalanceIndex: startIndexUint40,
                lastBalance: 0
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

        // Push a new balance check (or just overwrite the bps if the balance of the last check is still zero)
        if (lastBalanceCheck.balance > 0) {
            self._balanceChecks.push(BalanceCheck(uint16(newTotalBps), 0));
        } else {
            self._balanceChecks[startIndex].totalBps = uint16(newTotalBps);
        }

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
        uint currentBalanceCheckIndex = self._balanceChecks.length - 1;
        for (uint i = 0; i < accounts.length;) {
            AccountShare storage accountShare = self._accounts[accounts[i]];
            uint bps = accountShare.bps;
            uint endIndex = accountShare.endIndex;
            uint removeableAt = accountShare.removableAt;
            // The account share must be active to be removed
            require(MAX_INDEX > endIndex);
            // The current timestamp must be greater than the removeableAt timestamp (unless explicitly skipped)
            require(skipRemoveableAtCheck || currentTimestamp >= removeableAt);

            // Set the bps to 0, and the endIndex to be the current balance share index
            accountShare.bps = 0;
            accountShare.endIndex = uint40(currentBalanceCheckIndex);

            unchecked {
                subFromTotalBps += bps; // Can be unchecked, bps was checked when the account share was added
                i++;
            }
        }

        BalanceCheck memory currentBalanceCheck = self._balanceChecks[currentBalanceCheckIndex];

        // Underflow is impossible since all changes are always accounted for
        uint newTotalBps = currentBalanceCheck.totalBps - subFromTotalBps;

        // Push a new balance check (or just overwrite the bps if the balance of the last check is still zero)
        if (currentBalanceCheck.balance > 0) {
            self._balanceChecks.push(BalanceCheck(uint16(newTotalBps), 0));
        } else {
            self._balanceChecks[currentBalanceCheckIndex].totalBps = uint16(newTotalBps);
        }

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
     * @dev An account is considered to be finished with withdrawals when the account's "lastBalanceIndex" is greater
     * than the account's "endIndex"
     *
     * Returns true if the account has not been initialized with any shares yet
     */
    function _accountHasFinishedWithdrawals(
        BalanceShare storage self,
        address account
    ) private view returns (bool) {
        AccountShare storage accountShare = self._accounts[account];
        return accountShare.createdAt == 0 || accountShare.lastBalanceIndex > accountShare.endIndex;
    }

}