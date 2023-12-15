// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {BSStorage} from "./BSStorage.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {BatchArrayChecker} from "contracts/utils/BatchArrayChecker.sol";

/**
 * @title Account management for each balance share.
 * @author Ben Jett - @BCJdevelopment
 */
contract BSAccountsManagement is BSStorage {

    event BalanceShareTotalBPSUpdate(
        address indexed client,
        uint256 indexed balanceShareId,
        uint256 oldBps,
        uint256 newBps
    );

    event AccountShareBPSUpdate(
        address indexed client,
        uint256 indexed balanceShareId,
        address indexed account,
        uint256 newBps,
        uint256 periodIndex,
        uint256 removableAt
    );

    event AccountShareRemovableAtUpdate(
        address indexed client,
        uint256 indexed balanceShareId,
        address indexed account,
        uint256 removableAt,
        uint256 periodIndex
    );

    error BalanceSumCheckpointIndexOverflow(uint256 maxIndex);
    error InvalidAddress(address account);
    error AccountShareNoUpdate(address account);
    error AccountShareInvalidBps(address account, uint256 bps, uint256 maxBps);
    error UnauthorizedToEditAccountShares(address client, address msgSender);
    error AccountShareDoesNotExist(address account);
    error AccountShareIsCurrentlyLocked(address account, uint256 removableAt);
    error UpdateExceedsMaxTotalBps(uint256 newTotalBps, uint256 maxBps);

    function getAccountBps(
        address client,
        uint256 balanceShareId,
        address account
    ) public view returns (uint256 accountBps) {
        AccountShare storage _accountShare = _getBalanceShare(client, balanceShareId).accounts[account];
        accountBps = _accountShare.periods[_accountShare.periodIndex].bps;
    }

    function getAccountCurrentPeriodIndex(
        address client,
        uint256 balanceShareId,
        address account
    ) public view returns (uint256 currentPeriodIndex) {
        AccountShare storage _accountShare = _getBalanceShare(client, balanceShareId).accounts[account];
        currentPeriodIndex = _accountShare.periodIndex;
    }

    function getAccountDetails(
        address client,
        uint256 balanceShareId,
        address account
    ) public view returns (
        uint256 bps,
        uint256 removableAt,
        uint256 initializedAtBlock,
        uint256 currentPeriodIndex,
        uint256 maxCheckpointIterations
    ) {
        (bps, removableAt, initializedAtBlock, currentPeriodIndex, maxCheckpointIterations) =
            _getAccountDetailsForPeriod(
                _getBalanceShare(client, balanceShareId),
                account,
                type(uint256).max
            );
    }

    function getAccountDetailsForPeriod(
        address client,
        uint256 balanceShareId,
        address account,
        uint256 periodIndex
    ) public view returns (
        uint256 bps,
        uint256 removableAt,
        uint256 initializedAtBlock,
        uint256 maxCheckpointIterations
    ) {
        (bps, removableAt, initializedAtBlock,, maxCheckpointIterations) = _getAccountDetailsForPeriod(
            _getBalanceShare(client, balanceShareId),
            account,
            periodIndex
        );
    }

    function _getAccountDetailsForPeriod(
        BalanceShare storage _balanceShare,
        address account,
        uint256 periodIndex
    ) internal view returns (
        uint256 bps,
        uint256 removableAt,
        uint256 initializedAtBlock,
        uint256 maxPeriodIndex,
        uint256 maxCheckpointIterations
    ) {
        AccountShare storage _accountShare = _balanceShare.accounts[account];
        maxPeriodIndex = _accountShare.periodIndex;

        if (periodIndex == type(uint256).max) {
            periodIndex == maxPeriodIndex;
        }

        if (periodIndex > maxPeriodIndex) {
            revert InvalidAccountSharePeriodIndex(periodIndex, maxPeriodIndex);
        }

        AccountSharePeriod storage _accountSharePeriod = _accountShare.periods[periodIndex];
        (bps, removableAt, initializedAtBlock) = (
            _accountSharePeriod.bps,
            _accountSharePeriod.initializedAtBlock,
            _accountSharePeriod.removableAt
        );

        (uint256 startBalanceSumIndex, uint256 endBalanceSumIndex) = (
            _accountSharePeriod.startBalanceSumIndex,
            _accountSharePeriod.endBalanceSumIndex
        );

        maxCheckpointIterations = Math.min(
            endBalanceSumIndex,
            _balanceShare.balanceSumCheckpointIndex + 1
        ) - startBalanceSumIndex;
    }

    /**
     * Sets the provided accounts with the provided BPS values and removable at timestamps for the balance share ID. For
     * each account:
     * - If the account share DOES NOT currently exist for this balance share, this will create a new account share with
     * the provided BPS value and removable at timestamp.
     * - If the account share DOES currently exist for this balance share, this will update the account share with the
     * new BPS value and removable at timestamp.
     * @dev The msg.sender is considered the client. Only each individual client is authorized to make account share
     * updates.
     * @notice If the update decreases the current BPS share or removable at timestamp for the account, then the current
     * block.timestamp must be greater than the account's existing removable at timestamp.
     * @param balanceShareId The uint256 identifier of the client's balance share.
     * @param accounts An array of account addresses to update.
     * @param basisPoints An array of the new basis point share values for each account.
     * @param removableAts An array of the new removable at timestamps, before which the account's BPS cannot be
     * decreased.
     * @return totalBps The new total BPS for the balance share.
     */
    function setAccountShares(
        uint256 balanceShareId,
        address[] memory accounts,
        uint256[] memory basisPoints,
        uint256[] memory removableAts
    ) external returns (uint256 totalBps) {
        BatchArrayChecker.checkArrayLengths(accounts.length, basisPoints.length, removableAts.length);

        totalBps = _updateAccountShares(msg.sender, balanceShareId, accounts, basisPoints, removableAts);
    }

    /**
     * For the given balance share ID, updates the BPS share for each provided account, or creates a new BPS share for
     * accounts that do not already have an active BPS share (in which case the removable at timestamp will be zero).
     * @param balanceShareId The uint256 identifier of the client's balance share.
     * @param accounts An array of account addresses to update the BPS for.
     * @param basisPoints An array of the new basis point share values for each account.
     * @return totalBps The new total BPS for the balance share.
     */
    function setAccountSharesBps(
        uint256 balanceShareId,
        address[] memory accounts,
        uint256[] memory basisPoints
    ) external returns (uint256 totalBps) {
        BatchArrayChecker.checkArrayLengths(accounts.length, basisPoints.length);

        totalBps = _updateAccountShares(msg.sender, balanceShareId, accounts, basisPoints, new uint256[](0));
    }

    /**
     * Updates the removable at timestamps for the provided accounts. Reverts if the account does not have an active
     * BPS share.
     * @param balanceShareId The uint256 identifier of the client's balance share.
     * @param accounts An array of account addresses to update the BPS for.
     * @param removableAts An array of the new removable at timestamps, before which the account's BPS cannot be
     * decreased.
     */
    function setAccountSharesRemovableAts(
        uint256 balanceShareId,
        address[] memory accounts,
        uint256[] memory removableAts
    ) external {
        BatchArrayChecker.checkArrayLengths(accounts.length, removableAts.length);


        _updateAccountShares(msg.sender, balanceShareId, accounts, new uint256[](0), removableAts);
    }

    function updateAccountShareAsAccountOwner(
        address client,
        uint256 balanceShareId,
        uint256 newBasisPoints,
        uint256 newRemovableAt
    ) external {
        address[] memory accounts = new address[](1);
        accounts[0] = msg.sender;

        uint256[] memory basisPoints = new uint256[](1);
        basisPoints[0] = newBasisPoints;

        uint256[] memory removableAts = new uint256[](1);
        removableAts[0] = newRemovableAt;

        _updateAccountShares(client, balanceShareId, accounts, basisPoints, removableAts);
    }

    /**
     * @dev Private helper to update account shares by updating or pushing a new AccountSharePeriod.
     * @notice This helper assumes that array length equality checks are performed in the calling function. This
     * function will only check that the accounts array length is not zero.
     *
     * To only update basis points, pass removableAts array length of zero. Vice versa to only update removableAts.
     */
    function _updateAccountShares(
        address client,
        uint256 balanceShareId,
        address[] memory accounts,
        uint256[] memory basisPoints,
        uint256[] memory removableAts
    ) internal returns (uint256 newTotalBps) {
        {
            uint256 len = accounts.length;
             if (len == 0) {
                revert BatchArrayChecker.BatchArrayMissingItems();
            }

            if (
                (len != basisPoints.length && (removableAts.length > 0 && len != removableAts.length)) ||
                (len != removableAts.length && (basisPoints.length > 0 && len != basisPoints.length))
            ) {
                revert BatchArrayChecker.BatchArrayLengthMismatch();
            }
        }

        BalanceShare storage _balanceShare = _getBalanceShare(client, balanceShareId);

        uint256 balanceSumCheckpointIndex = _balanceShare.balanceSumCheckpointIndex;
        uint256 totalBps;

        // Block scope to unpack the current balanceSumCheckpoint "totalBps" and "hasBalances" values
        {
            BalanceSumCheckpoint storage _balanceSumCheckpoint =
                _balanceShare.balanceSumCheckpoints[balanceSumCheckpointIndex];
            totalBps = _balanceSumCheckpoint.totalBps;
            bool hasBalances = _balanceSumCheckpoint.hasBalances;

            // If hasBalances, increment to a new balance sum checkpoint if updating BPS and current totalBps > 0
            // Otherwise, just overwrite the BPS for the current BalanceSumCheckpoint
            if (hasBalances && basisPoints.length > 0 && totalBps > 0) {
                // Increment checkpoint index in memory and store the update
                unchecked {
                    _balanceShare.balanceSumCheckpointIndex = ++balanceSumCheckpointIndex;
                }

                // Don't allow the index to reach MAX_INDEX (end indices are non-inclusive)
                if (balanceSumCheckpointIndex >= MAX_INDEX) {
                    revert BalanceSumCheckpointIndexOverflow(MAX_INDEX);
                }
            }
        }

        // Track changes to total BPS
        newTotalBps = totalBps;

        // Loop through and update account share periods
        for (uint256 i = 0; i < accounts.length;) {
            address account = accounts[i];

            // No zero addresses
            if (account == address(0)) {
                revert InvalidAddress(account);
            }

            AccountShare storage _accountShare = _balanceShare.accounts[account];
            uint256 periodIndex = _accountShare.periodIndex;
            AccountSharePeriod storage _accountSharePeriod = _accountShare.periods[periodIndex];

            uint256 currentBps = _accountSharePeriod.bps;
            uint256 currentRemovableAt = _accountSharePeriod.removableAt;

            // New bps cannot exceed MAX_BPS, because math below uses unchecked to track totalBps changes
            // If a client did attempt to overflow the unchecked math, this check ensures that they would need to send
            // (2**256 - 1) / 10_000 basisPoints array items to overflow, which would exceed the max block gas
            uint256 newBps = basisPoints.length == 0 ? currentBps : basisPoints[i];
            if (newBps > MAX_BPS) {
                revert AccountShareInvalidBps(account, newBps, MAX_BPS);
            }

            // Fit removableAt into uint48 (inconsequential if provided value was greater than type(uint48).max)
            uint256 newRemovableAt = Math.min(
                removableAts.length == 0 ? currentRemovableAt : removableAts[i],
                type(uint48).max
            );

            // Revert if no update
            if (newBps == currentBps && newRemovableAt == currentRemovableAt) {
                revert AccountShareNoUpdate(account);
            }

            // If the client is not the msg.sender...
            if (msg.sender != client) {
                // Only update if msg.sender is account owner && they are not increasing BPS or removableAt
                if (
                    msg.sender != account ||
                    newBps > currentBps ||
                    newRemovableAt > currentRemovableAt
                ) {
                    revert UnauthorizedToEditAccountShares(client, msg.sender);
                }
            }

            // If decreasing bps or removableAt timestamp, check the account lock
            if (newBps < currentBps || newRemovableAt < currentRemovableAt) {
                // Current timestamp must be greater than the removableAt timestamp (unless msg.sender is owner)
                if (block.timestamp < currentRemovableAt && msg.sender != account) {
                    revert AccountShareIsCurrentlyLocked(account, currentRemovableAt);
                }
            }

            if (newBps != currentBps) {
                // If currentBps is greater than zero, then the account already has an active bps share
                // Otherwise, just overwrite the current zero BPS period with the updates
                if (currentBps > 0) {
                    // Set end index for current period, then increment period index and update the storage reference
                    _accountSharePeriod.endBalanceSumIndex = uint48(balanceSumCheckpointIndex);
                    _accountShare.periodIndex = ++periodIndex;
                    _accountSharePeriod = _accountShare.periods[periodIndex];
                }

                // Track totalBps changes (allow temporary underflows - total balances out after each account update)
                unchecked {
                    newTotalBps += newBps - currentBps;
                }

                // Store new period if the newBps value is greater than zero (otherwise leave uninitialized)
                if (newBps > 0) {
                    _accountSharePeriod.bps = uint16(newBps);
                    _accountSharePeriod.startBalanceSumIndex = uint48(balanceSumCheckpointIndex);
                    _accountSharePeriod.endBalanceSumIndex = uint48(MAX_INDEX);
                    _accountSharePeriod.initializedAtBlock = uint48(block.number);
                    _accountSharePeriod.removableAt = uint48(newRemovableAt);
                }

                // Log bps update
                emit AccountShareBPSUpdate(
                    client,
                    balanceShareId,
                    account,
                    newBps,
                    periodIndex,
                    newRemovableAt
                );
            } else {
                // No bps change, only updating removableAt
                // Revert if account share does not exist (account bps is zero)
                if (currentBps == 0) {
                    revert AccountShareDoesNotExist(account);
                }
                _accountSharePeriod.removableAt = uint48(newRemovableAt);

                // Log removableAt update
                emit AccountShareRemovableAtUpdate(
                    client,
                    balanceShareId,
                    account,
                    newRemovableAt,
                    periodIndex
                );
            }

            unchecked { ++i; }
        }

        // Update the new total BPS in the balance sum checkpoint
        if (newTotalBps > MAX_BPS) {
            revert UpdateExceedsMaxTotalBps(newTotalBps, MAX_BPS);
        }

        // Update the storage value (even if no change) because it might be a new balance sum checkpoint
        _balanceShare.balanceSumCheckpoints[balanceSumCheckpointIndex].totalBps = uint16(newTotalBps);

        if (newTotalBps != totalBps) {
            emit BalanceShareTotalBPSUpdate(client, balanceShareId, totalBps, newTotalBps);
        }
    }
}