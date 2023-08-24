// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

library BalanceShares {

    struct BalanceShare {
        // Tracks the balance remainder when processing account balance updates
        uint16 _balanceRemainder;
        // solhint-disable-next-line
        bytes30 __gap_unused_0;
        // New balanceCheck pushed every time totalBps changes, or when overflow occurs, max length is type(uint40).max
        BalanceCheck[] _balanceChecks;
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
        uint256 bps;
        uint256 removableAt;
        address[] approvedAddressesForWithdrawal;
    }

    uint256 constant private MAX_BPS = 10_000; // Max total BPS (1 basis point == 0.01%, which is 1 / 10_000)
    uint40 constant private MAX_INDEX = type(uint40).max;
    uint256 constant private MAX_CHECK_BALANCE_AMOUNT = type(uint240).max;

    error MissingNewAccountShares();
    error InvalidAddress(address account);
    error AccountAlreadyExists(address account);
    error AccountNotActive(address account);
    error AccountShareStillLocked(address account);
    error Unauthorized();
    error AccountWithdrawalsFinished();
    error ZeroValueNotAllowed();
    error CannotDecreaseAccountBPSToZero();
    error UpdateExceedsMaxBps(uint256 newTotalBps, uint256 maxBps);

    /**
     * @dev Adds the provided account shares to the total balance shares being tracked.
     * For accounts that cannot claim their withdrawals on their own (because they don't have functions to do so),
     * it is recommended to provide [address(0)] for the approvedAccountsForWithdrawal so that any address can claim
     * the withdrawal proceeds on behalf of the account.
     *
     * It is recommended that the host contract process current balance shares before adding additional accounts.
     */
    function addAccountShares(
        BalanceShare storage self,
        NewAccountShare[] calldata newAccountShares
    ) internal {
        if (newAccountShares.length == 0) revert MissingNewAccountShares();

        // Initialize the latestBalanceCheck
        BalanceCheck memory latestBalanceCheck = BalanceCheck(0, 0);

        // Get startIndex of the nextBalanceCheck (assumed to be equal to length since we are pushing new balanceCheck)
        uint256 startIndex = self._balanceChecks.length;

        // If length is greater than zero, then copy the last array element to the nextBalanceCheck
        if (startIndex > 0) {
            latestBalanceCheck = self._balanceChecks[startIndex - 1];
            // If the balance of the last element is zero, then we plan to just overwrite this checkpoint
            if (latestBalanceCheck.balance == 0) {
                startIndex -= 1;
            }
        } else {
            // If length not greater than zero, initialize the first element
            self._balanceChecks.push(latestBalanceCheck);
        }

        // Cache as uint40 for loop below, SafeCast ensures array length is no larger than type(uint40).max
        uint40 startIndexUint40 = SafeCast.toUint40(startIndex);

        // Loop through accounts and track BPS changes
        uint256 addToTotalBps;
        uint40 currentTimestamp = uint40(block.timestamp); // Cache timestamp in memory to save gas in loop

        for (uint256 i = 0; i < newAccountShares.length;) {
            NewAccountShare calldata newAccountShare = newAccountShares[i];

            // No zero addresses
            if (newAccountShare.account == address(0)) revert InvalidAddress(newAccountShare.account);
            // Check that the account has zeroed out previous balances (on the off chance that it existed previously)
            if (
                !_accountHasFinishedWithdrawals(self._accounts[newAccountShare.account])
            ) revert AccountAlreadyExists(newAccountShare.account);

            // We don't verify the BPS amount here, because total will be verified below
            addToTotalBps += newAccountShare.bps;
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
            unchecked { ++i; }
        }

        // Calculate the new totalBps, and make sure it is valid
        uint256 newTotalBps = latestBalanceCheck.totalBps + addToTotalBps;

        // Update the totalBps
        _updateTotalBps(self, latestBalanceCheck.balance, startIndex, newTotalBps);

    }

    /**
     * @dev Removes the specified accounts from receiving further shares. Does not process withdrawals. The receivers
     * will still have access to withdraw their balances that were accumulated prior to removal.
     *
     * Requires that the block.timestamp is greater than the account's "removableAt" parameter, or else throws an error.
     *
     * It is recommended that the host contract process current balance shares before removing accounts.
     */
    function removeAccountShares(
        BalanceShare storage self,
        address[] calldata accounts
    ) internal {
        uint256 subFromTotalBps;
        uint256 latestBalanceCheckIndex = self._balanceChecks.length - 1;
        for (uint256 i = 0; i < accounts.length;) {
            unchecked {
                // Can be unchecked, bps was checked when the account share was added
                subFromTotalBps += _destroyAccountShare(self, accounts[i], latestBalanceCheckIndex);
                ++i;
            }
        }

        // Update the totalBps
        BalanceCheck memory latestBalanceCheck = self._balanceChecks[latestBalanceCheckIndex];
        uint256 newTotalBps = latestBalanceCheck.totalBps - subFromTotalBps;
        _updateTotalBps(self, latestBalanceCheck.balance, latestBalanceCheckIndex, newTotalBps);
    }

    /**
     * @dev A helper function for allowing an AccountShare recipient to remove their own account.
     *
     * (_destroyAccountShare allows the msg.sender to destroy the account share before the removableAt timestamp)
     */
    function removeAccountShareSelf(
        BalanceShare storage self
    ) internal {
        uint256 latestBalanceCheckIndex = self._balanceChecks.length - 1;
        BalanceCheck memory latestBalanceCheck = self._balanceChecks[latestBalanceCheckIndex];
        uint256 newTotalBps =
            latestBalanceCheck.totalBps - _destroyAccountShare(self, msg.sender, latestBalanceCheckIndex);
        _updateTotalBps(self, latestBalanceCheck.balance, latestBalanceCheckIndex, newTotalBps);
    }

    /**
     * @dev Method to add to the total pool of balance available to the account shares, at the rate of:
     * balanceIncreasedBy * totalBps / 10_000
     * @param balanceIncreasedBy A uint256 representing how much the core balance increased by, which will be multiplied
     * by the totalBps for all active balance shares to be made available to those accounts.
     * @return balanceAddedToShares Returns the amount added to the balance shares, which should be accounted for in the
     * host contract.
     */
    function processBalance(
        BalanceShare storage self,
        uint256 balanceIncreasedBy
    ) internal returns (uint256 balanceAddedToShares) {
        uint256 length = self._balanceChecks.length;
        // Only continue if the length is greater than zero, otherwise returns zero by default
        if (length > 0) {
            BalanceCheck storage latestBalanceCheck = self._balanceChecks[length - 1];
            uint256 currentTotalBps = latestBalanceCheck.totalBps;
            if (currentTotalBps > 0) {
                balanceAddedToShares = _processBalance(self, currentTotalBps, balanceIncreasedBy);
                _addBalance(self, latestBalanceCheck, balanceAddedToShares);
            }
        }
    }

    /**
     * @dev A function to directly add a given amount to the balance shares. This amount should be accounted for in the
     * host contract.
     */
    function addBalanceToShares(
        BalanceShare storage self,
        uint256 amount
    ) internal {
        uint256 length = self._balanceChecks.length;
        if (length > 0) {
            BalanceCheck storage latestBalanceCheck = self._balanceChecks[length - 1];
            _addBalance(self, latestBalanceCheck, amount);
        }
    }

    /**
     * @dev Processes an account withdrawal, calculating the balance amount that should be paid out to the account. As a
     * result of this function, the balance amount to be paid out is marked as withdrawn for this account. The host
     * contract is responsible for ensuring this balance is paid out to the account as part of the transaction.
     *
     * Can only be processed if msg.sender is the account itself, or if msg.sender is approved, or if the account has
     * approved anyone (address(0) is approved).
     *
     * @return balanceToBePaid This is the balance that is marked as paid out for the account. The host contract should
     * pay this balance to the account as part of the withdrawal transaction.
     */
    function processAccountWithdrawal(
        BalanceShare storage self,
        address account
    ) internal returns (uint256) {

        // Authorize the msg.sender
        if (
            msg.sender != account &&
            !self._accountWithdrawalApprovals[account][msg.sender] &&
            !self._accountWithdrawalApprovals[account][address(0)]
        ) revert Unauthorized();

        AccountShare storage accountShare = self._accounts[account];
        (
            uint256 balanceToBePaid,
            uint256 lastBalanceCheckIndex,
            uint256 lastBalancePulled
        ) = _calculateAccountBalance(
            self,
            accountShare,
            true // Revert if the account is already completed their withdrawals, save the gas
        );

        // Save the account updates to storage
        accountShare.lastBalanceCheckIndex = uint40(lastBalanceCheckIndex);
        accountShare.lastBalancePulled = lastBalancePulled;
        accountShare.lastWithdrawnAt = uint40(block.timestamp);

        return balanceToBePaid;
    }

    /**
     * @dev Increases the account BPS, updating the total BPS and returning the new account BPS.
     * @return accountBps Returns the new account BPS.
     */
    function increaseAccountBps(
        BalanceShare storage self,
        address account,
        uint256 increaseBy
    ) internal returns (uint256) {
        if (increaseBy == 0) revert ZeroValueNotAllowed();
        AccountShare storage accountShare = self._accounts[account];
        // Account must not have finished withdrawals (this also ensures that the account has been initialized)
        if (_accountHasFinishedWithdrawals(accountShare)) revert AccountNotActive(account);
        uint256 newAccountBps = accountShare.bps + increaseBy;
        accountShare.bps = SafeCast.toUint16(newAccountBps);

        // Also update the totalBps
        uint256 latestBalanceCheckIndex = self._balanceChecks.length - 1;
        BalanceCheck memory latestBalanceCheck = self._balanceChecks[latestBalanceCheckIndex];
        _updateTotalBps(
            self,
            latestBalanceCheck.balance,
            latestBalanceCheckIndex,
            latestBalanceCheck.totalBps + increaseBy
        );
        return newAccountBps;
    }

    /**
     * @dev Function to decrease the basis points share for an account. Defaults to not allowing the bps decrease if the
     * current timestamp is earlier than the account's "removableAt" timestamp.
     */
    function decreaseAccountBps(
        BalanceShare storage self,
        address account,
        uint256 decreaseBy
    ) internal returns (uint256) {
        if (decreaseBy == 0) revert ZeroValueNotAllowed();
        AccountShare storage accountShare = self._accounts[account];
        // Account must not have finished withdrawals (this also ensures that the account has been initialized)
        if (_accountHasFinishedWithdrawals(accountShare)) revert AccountNotActive(account);
        (
            uint256 bps,
            uint256 removableAt
        ) = (
            accountShare.bps,
            accountShare.removableAt
        );
        // Cannot decrease to zero (should call remove account share in that case)
        if (decreaseBy >= bps) revert CannotDecreaseAccountBPSToZero();
        // The current timestamp must be greater than the removableAt timestamp (unless explicitly skipped)
        if (block.timestamp < removableAt && msg.sender != account) revert AccountShareStillLocked(account);

        // Update the account bps
        uint256 newAccountBps = bps - decreaseBy;
        accountShare.bps = uint16(newAccountBps);

        // Update the totalBps too
        uint256 latestBalanceCheckIndex = self._balanceChecks.length - 1;
        BalanceCheck memory latestBalanceCheck = self._balanceChecks[latestBalanceCheckIndex];
        _updateTotalBps(
            self,
            latestBalanceCheck.balance,
            latestBalanceCheckIndex,
            latestBalanceCheck.totalBps - decreaseBy
        );

        return newAccountBps;
    }

    /**
     * @dev Helper method to update the "removableAt" timestamp for an account. Can only decrease if msg.sender is the
     * account, otherwise can only increase.
     */
    function updateAccountRemovableAt(
        BalanceShare storage self,
        address account,
        uint256 newRemovableAt
    ) internal {
        uint256 currentRemovableAt = self._accounts[account].removableAt;
        // If msg.sender, then can decrease, otherwise can only increase
        // NOTE: This also ensures uninitiated accounts don't change anything as well. If msg.sender is the account,
        // then currentRemovableAt will be zero, which will throw an error
        if (
            msg.sender == account ?
            newRemovableAt >= currentRemovableAt :
            newRemovableAt <= currentRemovableAt
        ) revert Unauthorized();
        self._accounts[account].removableAt = SafeCast.toUint40(newRemovableAt);
    }

    /**
     * @dev Approve the provided list of addresses to initiate withdrawal on the account. Approve address(0) to allow
     * anyone.
     */
    function approveAddressesForWithdrawal(
        BalanceShare storage self,
        address account,
        address[] calldata approvedAddresses
    ) internal {
        for (uint256 i = 0; i < approvedAddresses.length;) {
            self._accountWithdrawalApprovals[account][approvedAddresses[i]] = true;
            unchecked { ++i; }
        }
    }

    /**
     * @dev Unapprove the provided list of addresses for initiating withdrawals on the account.
     */
    function unapproveAddressesForWithdrawal(
        BalanceShare storage self,
        address account,
        address[] calldata unapprovedAddresses
    ) internal {
        for (uint256 i = 0; i < unapprovedAddresses.length;) {
            self._accountWithdrawalApprovals[account][unapprovedAddresses[i]] = false;
            unchecked { ++i; }
        }
    }

    /**
     * @dev A function for changing the address that an account receives its shares to. This is only callable by the
     * account owner. A list of approved addresses for withdrawal can be provided.
     *
     * Note that by default, if the address(0) was approved (meaning anyone can process a withdrawal to the account),
     * then address(0) will be approved for the new account address as well.
     *
     * @param account The address for the current account share (which must be msg.sender)
     * @param newAccount The new address to copy the account share over to.
     * @param approvedAddresses A list of addresses to be approved for processing withdrawals to the account receiver.
     */
    function changeAccountAddress(
        BalanceShare storage self,
        address account,
        address newAccount,
        address[] calldata approvedAddresses
    ) internal {
        if (msg.sender != account) revert Unauthorized();
        if (newAccount == address(0)) revert InvalidAddress(newAccount);
        // Copy it over
        self._accounts[newAccount] = self._accounts[account];
        // Zero out the old account
        delete self._accounts[account];

        // Approve addresses
        approveAddressesForWithdrawal(self, newAccount, approvedAddresses);

        if (self._accountWithdrawalApprovals[account][address(0)]) {
            self._accountWithdrawalApprovals[newAccount][address(0)] = true;
        }
    }

    /**
     * @dev The total basis points sum for all currently active account shares.
     * @return totalBps An integer representing the total basis points sum. 1 basis point = 0.01%
     */
    function totalBps(
        BalanceShare storage self
    ) internal view returns (uint256) {
        uint256 length = self._balanceChecks.length;
        return length > 0 ?
            self._balanceChecks[length - 1].totalBps :
            0;
    }

    /**
     * @dev A function to calculate the balance to be added to the shares provided the amount the balance increased by
     * and the current total BPS. Returns both the calculated balance to be added to the balance shares, as well as the
     * remainder (useful for storing for next time).
     * @param balanceIncreasedBy A uint256 representing how much the core balance increased by, which will be multiplied
     * by the totalBps for all active balance shares to be made available to those accounts.
     * @return balanceToAddToShares The calculated balance to add the shares
     */
    function calculateBalanceToAddToShares(
        BalanceShare storage self,
        uint256 balanceIncreasedBy
    ) internal view returns (uint256 balanceToAddToShares) {
        uint256 currentTotalBps = totalBps(self);
        if (currentTotalBps > 0) {
            (balanceToAddToShares,) = _calculateBalanceShare(self, balanceIncreasedBy, currentTotalBps);
        }
    }

    /**
     * @dev Returns the current withdrawable balance for an account share.
     * @return balanceAvailable The balance available for withdraw from this account.
     */
    function accountBalance(
        BalanceShare storage self,
        address account
    ) internal view returns (uint256) {
        AccountShare storage accountShare = self._accounts[account];
        (uint256 balanceAvailable,,) = _calculateAccountBalance(
            self,
            accountShare,
            false // Show the zero balance
        );
        return balanceAvailable;
    }

    /**
     * @dev A helper function to predict the account balance with an additional "balanceIncreasedBy" parameter (assuming
     * the state has not been updated to match yet).
     * @return accountBalance Returns the predicted account balance.
     */
    function predictedAccountBalance(
        BalanceShare storage self,
        address account,
        uint256 balanceIncreasedBy
    ) internal view returns (uint256) {
        AccountShare storage accountShare = self._accounts[account];
        (uint256 balanceAvailable,,) = _calculateAccountBalance(
            self,
            accountShare,
            false
        );
        (uint256 addedTotalBalance,) = _calculateBalanceShare(
            self,
            balanceIncreasedBy,
            accountShare.bps
        );
        return balanceAvailable + Math.mulDiv(addedTotalBalance, accountShare.bps, MAX_BPS);
    }

    /**
     * @dev Returns a bool indicating whether or not the address is approved for withdrawal on the specified account.
     */
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
     * - removableAt
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
     * @dev An account is considered to be finished with withdrawals when the account's "lastBalanceCheckIndex" is
     * greater than the account's "endIndex".
     *
     * Returns true if the account has not been initialized with any shares yet.
     */
    function accountHasFinishedWithdrawals(
        BalanceShare storage self,
        address account
    ) internal view returns (bool) {
        return _accountHasFinishedWithdrawals(self._accounts[account]);
    }

    function _destroyAccountShare(
        BalanceShare storage self,
        address account,
        uint256 latestBalanceCheckIndex
    ) private returns (uint256) {
        AccountShare storage accountShare = self._accounts[account];
        uint256 bps = accountShare.bps;
        uint256 endIndex = accountShare.endIndex;
        uint256 removableAt = accountShare.removableAt;
        // The account share must be active to be removed
        if (endIndex != MAX_INDEX) revert AccountNotActive(account);
        // The current timestamp must be greater than the removableAt timestamp (unless the msg.sender owns the account)
        if (block.timestamp < removableAt && msg.sender != account) revert AccountShareStillLocked(account);

        // Set the bps to 0, and the endIndex to be the current balance share index
        accountShare.bps = 0;
        accountShare.endIndex = uint40(latestBalanceCheckIndex);
        return bps;
    }

    /**
     * @dev Private function that takes the balanceIncreasedBy, adds the previous _balanceRemainder, and returns the
     * balanceToAddToShares, updating the stored _balanceRemainder in the process.
     */
    function _processBalance(
        BalanceShare storage self,
        uint256 currentTotalBps,
        uint256 balanceIncreasedBy
    ) private returns (uint256) {
        (
            uint256 balanceToAddToShares,
            uint256 newBalanceRemainder
        ) = _calculateBalanceShare(self, balanceIncreasedBy, currentTotalBps);
        // Update with the new remainder
        self._balanceRemainder = SafeCast.toUint16(newBalanceRemainder);
        return balanceToAddToShares;
    }

    /**
     * @dev Private function that returns the balanceToAddToShares, and the mulmod remainder of the operation.
     * NOTE: This function adds the previous _balanceRemainder to the balanceIncreasedBy parameter before running the
     * calculations.
     */
    function _calculateBalanceShare(
        BalanceShare storage self,
        uint256 balanceIncreasedBy,
        uint256 bps
    ) private view returns (uint256, uint256) {
        balanceIncreasedBy += self._balanceRemainder; // Adds the previous remainder into the calculation
        return (
            Math.mulDiv(balanceIncreasedBy, bps, MAX_BPS),
            mulmod(balanceIncreasedBy, bps, MAX_BPS)
        );
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
                uint256 currentBalance = latestBalanceCheck.balance;
                // Loop until break
                while (true) {
                    // Can only increase current balanceCheck up to the MAX_CHECK_BALANCE_AMOUNT
                    uint256 balanceIncrease = Math.min(amount, MAX_CHECK_BALANCE_AMOUNT - currentBalance);
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
     * @dev Private function to calculate the current balance owed to the AccountShare.
     * @return accountBalanceOwed The balance owed to the account share.
     * @return lastBalanceCheckIndex The resulting lastBalanceCheckIndex for the account.
     * @return lastBalancePulled The resulting lastBalancePulled for the account.
     */
    function _calculateAccountBalance(
        BalanceShare storage self,
        AccountShare storage accountShare,
        bool revertOnWithdrawalsFinished
    ) private view returns(
        uint256 accountBalanceOwed,
        uint256,
        uint256
    ) {
        (
            uint256 bps,
            uint256 createdAt,
            uint256 endIndex,
            uint256 lastBalanceCheckIndex,
            uint256 lastBalancePulled
        ) = (
            accountShare.bps,
            accountShare.createdAt,
            accountShare.endIndex,
            accountShare.lastBalanceCheckIndex,
            accountShare.lastBalancePulled
        );

        // If account is not active or is already finished with withdrawals, return zero
        if (_accountHasFinishedWithdrawals(createdAt, lastBalanceCheckIndex, endIndex)) {
            if (revertOnWithdrawalsFinished) {
                revert AccountWithdrawalsFinished();
            }
            return (accountBalanceOwed, lastBalanceCheckIndex, lastBalancePulled);
        }

        uint256 latestBalanceCheckIndex = self._balanceChecks.length - 1;

        // Process each balanceCheck while in range of the endIndex, summing the total balance to be paid
        while (lastBalanceCheckIndex <= endIndex) {
            BalanceCheck memory balanceCheck = self._balanceChecks[lastBalanceCheckIndex];
            uint256 diff = balanceCheck.balance - lastBalancePulled;
            if (diff > 0 && balanceCheck.totalBps > 0) {
                // For each check, add (balanceCheck.balance - lastBalancePulled) * (accountBps / balanceCheck.totalBps)
                accountBalanceOwed += Math.mulDiv(diff, bps, balanceCheck.totalBps);
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
             * This is the desired behavior. See the private _accountHasFinishedWithdrawals function. This considers an
             * account to be finished with withdrawals once the lastBalanceCheckIndex is greater than the endIndex.
             */
            unchecked {
                lastBalanceCheckIndex += 1;
                lastBalancePulled = 0;
            }
        }

        return (accountBalanceOwed, lastBalanceCheckIndex, lastBalancePulled);

    }

    /**
     * @dev Helper method for updating the totalBps for a BalanceShare. Checks if it needs to push a new BalanceCheck
     * item to the array, or if it can just update the totalBps for the latest item (if the balance is already zero).
     */
    function _updateTotalBps(
        BalanceShare storage self,
        uint256 latestBalance,
        uint256 latestBalanceCheckIndex,
        uint256 newTotalBps
    ) private {
        if (newTotalBps > MAX_BPS) revert UpdateExceedsMaxBps(newTotalBps, MAX_BPS);
        // If the latestBalance is greater than 0, then push a new item, otherwise just update the current item
        if (latestBalance > 0) {
            self._balanceChecks.push(BalanceCheck(uint16(newTotalBps), 0));
        } else {
            self._balanceChecks[latestBalanceCheckIndex].totalBps = uint16(newTotalBps);
        }
    }

    /**
     * @dev Overload for when the reference is already present
     */
    function _accountHasFinishedWithdrawals(
        AccountShare storage accountShare
    ) private view returns (bool) {
        (uint256 createdAt, uint256 lastBalanceCheckIndex, uint256 endIndex) = (
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
        uint256 createdAt,
        uint256 lastBalanceCheckIndex,
        uint256 endIndex
    ) private pure returns (bool) {
        return createdAt == 0 || lastBalanceCheckIndex > endIndex;
    }

}