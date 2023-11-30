// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {BasisPoints} from "contracts/libraries/BasisPoints.sol";
import {IArrayLengthErrors} from "contracts/interfaces/IArrayLengthErrors.sol";
import {IBalanceSharesManager} from "contracts/executor/interfaces/IBalanceSharesManager.sol";

/**
 * @title A singleton contract for clients to manage account shares (in basis points) for ETH/ERC20 assets.
 *
 * @author Ben Jett - @BCJdevelopment
 *
 * @dev This singleton allows any client to create balance shares with one or more account shares for each balance
 * share. Each account share is denoted in basis points.
 *
 * The main point of this singleton is to significantly reduce gas costs for a protocol's users by releasing assets to
 * account share recipients in batch withdrawals. A client only needs to specify a balance share ID, for which they can
 * setup any account shares they choose, and add balances to the balance share to be withdrawn by the individual account
 * share recipients at any point in time.
 *
 * The internal accounting of this contract also allows a client to make updates to a balance share (such as
 * adding/removing account shares, updating the BPS for an account, etc.) at any point in time, and account recipients
 * will still be able to withdraw their pro rata claim to the accumulated balance share assets at any point in time.
 *
 * A hypothetical example: 4 accounts need to each receive 5% of the deposit amount for an on-chain mint. Rather than
 * paying huge gas costs to send 5% of the deposit amount to 4 different accounts every time asset(s) are minted, the
 * minting contract creates a new balance share ID for deposits, adds the 4 accounts with 5% each, and then sends 20% of
 * the deposit amount for each mint transaction to this contract. Then, each individual account recipient can process a
 * batch withdrawal of their claim to the accumulated balance share assets at any point in time.
 *
 * Account share recipients can also give permissions to other accounts (or open permissions to any account) to process
 * withdrawals on their behalf (still sending the assets to their own account).
 */
contract BalanceSharesSingleton {
    using BasisPoints for uint256;

    mapping(address client => mapping(uint256 balanceShareId => BalanceShare)) private _balanceShares;

    /**
     * @dev IMPORTANT: Changing the order of variables in this struct could affect the optimized mapping retrieval
     * functions at the bottom of the file.
     */
    struct BalanceShare {
        // New balance sum checkpoint created every time totalBps changes, or when asset sum overflow occurs
        // Mapping, not array, to avoid storage collisions
        uint256 balanceSumCheckpointIndex;
        mapping(uint256 balanceSumIndex => BalanceSumCheckpoint) balanceSumCheckpoints;

        mapping(address => AccountShare) accounts;

        // TODO: Client approval of account withdrawal per balance share
    }

    /**
     * @dev IMPORTANT: Changing the order of variables in this struct could affect the optimized mapping retrieval
     * functions at the bottom of the file.
     */
    struct BalanceSumCheckpoint {
        uint256 totalBps; // Tracks the totalBps among all account shares for this balance sum checkpoint
        mapping(address asset => BalanceSum) balanceSums;
    }

    /**
     * @dev Storing asset remainders in the BalanceSum struct will not carry asset remainders over to a new
     * BalanceSumCheckpoint, but packing the storage with the asset balance avoids writing to an extra storage slot
     * when a new balance is processed and added to the balance sum. We optimize for the gas usage here, as new
     * checkpoints will only be written when the total BPS changes or an asset overflows, both of which are not likely
     * to be as common of events as the actual balance processing itself. And the point of this library is to offload
     * gas costs for balance shares from the users to the account recipients.
     */
    struct BalanceSum {
        uint48 remainder;
        uint208 balance;
    }

    struct AccountShare {
        // Store each account share period for the account, sequentially
        // Mapping, not array, to avoid storage collisions
        uint256 periodIndex;
        mapping(uint256 checkpointIndex => AccountSharePeriod) periods;
    }

    struct AccountSharePeriod {
        // The account's BPS share this period
        uint16 bps;
        // Balance sum index where this account share period begins (inclusive)
        uint48 startBalanceSumIndex;
        // Balance sum index where this account share period ends, or MAX_INDEX when active (non-inclusive)
        uint48 endBalanceSumIndex;
        // Block number this checkpoint was initialized
        uint48 initializedAt;
        // Timestamp in seconds at which the account share bps can be decreased or removed by the client
        uint48 removableAt;
        // Tracks the current balance sum position for the last withdrawal per asset
        mapping(address asset => AccountCurrentBalanceSum) currentAssetBalanceSum;
    }

    struct AccountCurrentBalanceSum {
        uint48 currentBalanceSumIndex; // The current asset balance check index for the account
        uint208 previousBalanceSumAtWithdrawal; // The asset balance when it was last withdrawn by the account
    }

    // HELPER CONSTANTS
    uint256 constant private MAX_INDEX = type(uint48).max;
    uint256 constant private MAX_BALANCE_SUM = type(uint208).max;

    event AccountShareBpsUpdate(
        address indexed client,
        uint256 indexed balanceShareId,
        address indexed account,
        uint256 newBps,
        uint256 period
    );

    event AccountShareRemovableAtUpdate(
        address indexed client,
        uint256 indexed balanceShareId,
        address indexed account,
        uint256 removableAt,
        uint256 period
    );

    error BalanceSumCheckpointIndexOverflow(uint256 maxIndex);
    error InvalidAddress(address account);
    error AccountShareAlreadyExists(address account);
    error AccountShareDoesNotExist(address account);
    error AccountShareNoUpdate(address account);
    error AccountShareIsCurrentlyLocked(address account, uint256 removableAt);
    error UpdateExceedsMaxTotalBps(uint256 newTotalBps, uint256 maxBps);

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
     * @param balanceShareId The uint256 identifier of the balance share.
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
        if (
            accounts.length != basisPoints.length ||
            accounts.length != removableAts.length
        ) {
            revert IArrayLengthErrors.MismatchingArrayLengths();
        }

        totalBps = _updateAccountShares(msg.sender, balanceShareId, accounts, basisPoints, removableAts);
    }

    /**
     * For the given balance share ID, updates the BPS share for each provided account, or creates a new BPS share for
     * accounts that do not already have an active BPS share (in which case the removable at timestamp will be zero).
     * @param balanceShareId The uint256 identifier of the balance share.
     * @param accounts An array of account addresses to update the BPS for.
     * @param basisPoints An array of the new basis point share values for each account.
     * @return totalBps The new total BPS for the balance share.
     */
    function setAccountSharesBps(
        uint256 balanceShareId,
        address[] memory accounts,
        uint256[] memory basisPoints
    ) external returns (uint256 totalBps) {
        if (accounts.length != basisPoints.length) {
            revert IArrayLengthErrors.MismatchingArrayLengths();
        }

        totalBps = _updateAccountShares(msg.sender, balanceShareId, accounts, basisPoints, new uint256[](0));
    }

    /**
     * Updates the removable at timestamps for the provided accounts. Reverts if the account does not have an active
     * BPS share.
     * @param balanceShareId The uint256 identifier of the balance share.
     * @param accounts An array of account addresses to update the BPS for.
     * @param removableAts An array of the new removable at timestamps, before which the account's BPS cannot be
     * decreased.
     */
    function setAccountSharesRemovableAts(
        uint256 balanceShareId,
        address[] memory accounts,
        uint256[] memory removableAts
    ) external {
        if (accounts.length != removableAts.length) {
            revert IArrayLengthErrors.MismatchingArrayLengths();
        }

        _updateAccountShares(msg.sender, balanceShareId, accounts, new uint256[](0), removableAts);
    }

    /**
     * @dev Private helper to update account shares by updating or pushing a new AccountSharePeriod.
     * @notice This helper assumes that array length equality checks are performed in the calling function. This
     * function will only check that the accounts array length is not zero.
     *
     * To only update basis points, pass removableAts array length of zero. Vice versa for only updating removableAts.
     */
    function _updateAccountShares(
        address client,
        uint256 balanceShareId,
        address[] memory accounts,
        uint256[] memory basisPoints,
        uint256[] memory removableAts
    ) internal returns (uint256 newTotalBps) {
        if (accounts.length == 0) {
            revert IArrayLengthErrors.MissingArrayItems();
        }

        BalanceShare storage _balanceShare = _getBalanceShare(client, balanceShareId);

        uint256 balanceSumCheckpointIndex = _balanceShare.balanceSumCheckpointIndex;
        uint256 totalBps = _balanceShare.balanceSumCheckpoints[balanceSumCheckpointIndex].totalBps;
        // Increment to a new balance sum checkpoint if we are updating basis points and the current totalBps > 0
        if (basisPoints.length > 0 && totalBps > 0) {
            // Increment checkpoint index in memory and store the update
            unchecked {
                _balanceShare.balanceSumCheckpointIndex = ++balanceSumCheckpointIndex;
            }

            // Don't allow the index to reach MAX_INDEX (end indices are non-inclusive)
            if (balanceSumCheckpointIndex >= MAX_INDEX) {
                revert BalanceSumCheckpointIndexOverflow(MAX_INDEX);
            }
        }

        // Track changes to total BPS
        uint256 increaseTotalBpsBy;
        uint256 decreaseTotalBpsBy;

        // Loop through and update account share periods
        for (uint256 i = 0; i < accounts.length;) {
            // No zero addresses
            if (accounts[i] == address(0)) {
                revert InvalidAddress(accounts[i]);
            }

            AccountShare storage _accountShare = _balanceShare.accounts[accounts[i]];
            AccountSharePeriod storage _accountSharePeriod = _accountShare.periods[_accountShare.periodIndex];

            uint256 currentBps = _accountSharePeriod.bps;
            uint256 currentRemovableAt = _accountSharePeriod.removableAt;

            // No uint16 check on bps because when updating total, it will revert if the total is greater than 10_000
            uint256 newBps = basisPoints.length == 0 ? currentBps : basisPoints[i];
            // Fit removableAt into uint48 (inconsequential if provided value was greater than type(uint48).max)
            uint256 newRemovableAt = Math.min(
                type(uint48).max,
                removableAts.length == 0 ? currentRemovableAt : removableAts[i]
            );

            // Revert if no update
            if (newBps == currentBps && newRemovableAt == currentRemovableAt) {
                revert AccountShareNoUpdate(accounts[i]);
            }

            // If decreasing bps or decreasing removableAt timestamp, check the account lock
            if (newBps < currentBps || newRemovableAt < currentRemovableAt) {
                // Current timestamp must be greater than the removableAt timestamp (unless msg.sender is owner)
                if (block.timestamp < currentRemovableAt && msg.sender != accounts[i]) {
                    revert AccountShareIsCurrentlyLocked(accounts[i], currentRemovableAt);
                }
            }

            if (newBps != currentBps) {
                // If currentBps is greater than zero, then the account already has an active bps share
                if (currentBps > 0) {
                    // Set end index for current period, then increment period index and update the storage reference
                    _accountSharePeriod.endBalanceSumIndex = uint48(balanceSumCheckpointIndex);
                    _accountSharePeriod = _accountShare.periods[++_accountShare.periodIndex];
                }

                // Track bps changes
                if (newBps > currentBps) {
                    increaseTotalBpsBy += newBps - currentBps;
                } else {
                    decreaseTotalBpsBy += currentBps - newBps;
                }

                // Store new period if the newBps value is greater than zero (otherwise leave uninitialized)
                if (newBps > 0) {
                    _accountSharePeriod.bps = uint16(newBps);
                    _accountSharePeriod.startBalanceSumIndex = uint48(balanceSumCheckpointIndex);
                    _accountSharePeriod.endBalanceSumIndex = uint48(MAX_INDEX);
                    _accountSharePeriod.initializedAt = uint48(block.number);
                    _accountSharePeriod.removableAt = uint48(newRemovableAt);
                }
            } else {
                // No bps change, only updating removableAt
                // Revert if account share does not already exist
                if (currentBps == 0) {
                    revert AccountShareDoesNotExist(accounts[i]);
                }
                _accountSharePeriod.removableAt = uint48(newRemovableAt);
            }

            unchecked { ++i; }
        }

        // Calculate the new total bps, and update in the balance sum checkpoint
        newTotalBps = totalBps + increaseTotalBpsBy - decreaseTotalBpsBy;
        if (newTotalBps > BasisPoints.MAX_BPS) {
            revert UpdateExceedsMaxTotalBps(newTotalBps, BasisPoints.MAX_BPS);
        }

        _balanceShare.balanceSumCheckpoints[balanceSumCheckpointIndex].totalBps = newTotalBps;
    }

    function mockProcessBalanceShareIncrease(
        address client,
        uint256 balanceShareId,
        address asset,
        uint256 balanceIncreasedBy
    ) external view returns (uint256 amountToAllocate) {
        (amountToAllocate,,) = _calculateBalanceShareAllocation(
            _getBalanceShare(client, balanceShareId),
            asset,
            balanceIncreasedBy
        );
    }

    function mockProcessBalanceShareIncrease(
        uint256 balanceShareId,
        address asset,
        uint256 balanceIncreasedBy
    ) external view returns (uint256 amountToAllocate) {
        (amountToAllocate,,) = _calculateBalanceShareAllocation(
            _getBalanceShare(msg.sender, balanceShareId),
            asset,
            balanceIncreasedBy
        );
    }

    function processBalanceShareIncrease(
        address client,
        uint256 balanceShareId,
        address asset,
        uint256 balanceIncreasedBy
    ) external payable returns (uint256 amountAllocatedToShares) {
        amountAllocatedToShares = _processBalanceShareIncrease(
            _getBalanceShare(client, balanceShareId),
            asset,
            balanceIncreasedBy
        );
    }

    function processBalanceShareIncrease(
        uint256 balanceShareId,
        address asset,
        uint256 balanceIncreasedBy
    ) external payable returns (uint256 amountAllocatedToShares) {
        amountAllocatedToShares = _processBalanceShareIncrease(
            _getBalanceShare(msg.sender, balanceShareId),
            asset,
            balanceIncreasedBy
        );
    }

    function _calculateBalanceShareAllocation(
        BalanceShare storage _balanceShare,
        address asset,
        uint256 balanceIncreasedBy
    ) internal view returns (
        uint256 amountToAllocate,
        uint256 newAssetRemainder,
        BalanceSumCheckpoint storage _currentBalanceSumCheckpoint
    ) {
        _currentBalanceSumCheckpoint = _getCurrentBalanceSumCheckpoint(_balanceShare);

        uint256 totalBps = _currentBalanceSumCheckpoint.totalBps;
        if (totalBps > 0) {
            uint256 currentAssetRemainder = _getBalanceSum(_currentBalanceSumCheckpoint, asset).remainder;
            balanceIncreasedBy += currentAssetRemainder;

            amountToAllocate = balanceIncreasedBy.bps(totalBps);
            newAssetRemainder = balanceIncreasedBy.bpsMulmod(totalBps);
        }
    }

    function _processBalanceShareIncrease(
        BalanceShare storage _balanceShare,
        address asset,
        uint256 balanceIncreasedBy
    ) internal returns (uint256 amountAllocatedToShares) {
        // Get the allocation amount
        (
            uint256 amountToAllocate,
            uint256 newAssetRemainder,
            BalanceSumCheckpoint storage _currentBalanceSumCheckpoint
        ) = _calculateBalanceShareAllocation(
            _balanceShare,
            asset,
            balanceIncreasedBy
        );

        // Transfer funds here, and allocate to the balance share
        // TODO: SAFE TRANSFER OF FUNDS (COULD MAYBE ADD IN THE ADD BALANCE TO SHARES FUNCTION)

        BalanceSum storage _balanceSum = _addAssetToBalanceShare(
            _balanceShare,
            _currentBalanceSumCheckpoint,
            asset,
            amountToAllocate
        );

        // Update the remainder for the checkpoint
        _balanceSum.remainder = uint48(newAssetRemainder);

        amountAllocatedToShares = amountToAllocate;
    }

    /**
     * @dev Internal helper function that adds the provided asset amount to the balance sum checkpoint.
     * @notice IMPORTANT: This function assumes the provided _balanceSumCheckpoint is the current checkpoint (at
     * the current balanceSumCheckpointIndex).
     */
    function _addAssetToBalanceShare(
        BalanceShare storage _balanceShare,
        BalanceSumCheckpoint storage _balanceSumCheckpoint,
        address asset,
        uint256 amountToAllocate
    ) internal returns (
        BalanceSum storage _currentBalanceSum
    ) {
        BalanceSumCheckpoint storage _currentBalanceSumCheckpoint = _balanceSumCheckpoint;
        _currentBalanceSum = _getBalanceSum(_currentBalanceSumCheckpoint, asset);

        if (amountToAllocate > 0) {
            unchecked {
                uint256 currentBalance = _currentBalanceSum.balance;
                uint256 balanceIncrease;
                while (true) {
                    // For each checkpoint, the balance cannot exceed MAX_BALANCE_SUM

                    balanceIncrease = Math.min(amountToAllocate, MAX_BALANCE_SUM - currentBalance);
                    _currentBalanceSum.balance = uint208(currentBalance + balanceIncrease);

                    // Finished once the allocation reaches zero
                    amountToAllocate -= balanceIncrease;
                    if (amountToAllocate == 0) {
                        break;
                    }

                    // Increment the checkpoint index, update the BalanceSumCheckpoint reference (copy the totalBps)
                    uint256 totalBps = _currentBalanceSumCheckpoint.totalBps;
                    _currentBalanceSumCheckpoint =
                        _balanceShare.balanceSumCheckpoints[++_balanceShare.balanceSumCheckpointIndex];
                    _currentBalanceSumCheckpoint.totalBps = totalBps;
                    // Reset currentBalance to zero
                    currentBalance = 0;
                    // Update the BalanceSum reference
                    _currentBalanceSum = _getBalanceSum(_currentBalanceSumCheckpoint, asset);
                }
            }
        }
    }

    // /**
    //  * @dev Processes an account withdrawal, calculating the balance amount that should be paid out to the account. As a
    //  * result of this function, the balance amount to be paid out is marked as withdrawn for this account. The host
    //  * contract is responsible for ensuring this balance is paid out to the account as part of the transaction.
    //  *
    //  * Can only be processed if msg.sender is the account itself, or if msg.sender is approved, or if the account has
    //  * approved anyone (address(0) is approved).
    //  *
    //  * @return balanceToBePaid This is the balance that is marked as paid out for the account. The host contract should
    //  * pay this balance to the account as part of the withdrawal transaction.
    //  */
    // function processAccountWithdrawal(
    //     BalanceShare storage _self,
    //     address account
    // ) internal returns (uint256) {

    //     // Authorize the msg.sender
    //     if (
    //         msg.sender != account &&
    //         !_self._accountWithdrawalApprovals[account][msg.sender] &&
    //         !_self._accountWithdrawalApprovals[account][address(0)]
    //     ) revert Unauthorized();

    //     AccountShare storage accountShare = _self._accounts[account];
    //     (
    //         uint256 balanceToBePaid,
    //         uint256 lastBalanceCheckIndex,
    //         uint256 lastBalancePulled
    //     ) = _calculateAccountBalance(
    //         _self,
    //         accountShare,
    //         true // Revert if the account is already completed their withdrawals, save the gas
    //     );

    //     // Save the account updates to storage
    //     accountShare.lastBalanceCheckIndex = uint40(lastBalanceCheckIndex);
    //     accountShare.lastBalancePulled = lastBalancePulled;
    //     accountShare.lastWithdrawnAt = uint40(block.timestamp);

    //     return balanceToBePaid;
    // }



    // /**
    //  * @dev Helper method to update the "removableAt" timestamp for an account. Can only decrease if msg.sender is the
    //  * account, otherwise can only increase.
    //  */
    // function updateAccountRemovableAt(
    //     BalanceShare storage _self,
    //     address account,
    //     uint256 newRemovableAt
    // ) internal {
    //     uint256 currentRemovableAt = _self._accounts[account].removableAt;
    //     // If msg.sender, then can decrease, otherwise can only increase
    //     // NOTE: This also ensures uninitiated accounts don't change anything as well. If msg.sender is the account,
    //     // then currentRemovableAt will be zero, which will throw an error
    //     if (
    //         msg.sender == account ?
    //         newRemovableAt >= currentRemovableAt :
    //         newRemovableAt <= currentRemovableAt
    //     ) revert Unauthorized();
    //     _self._accounts[account].removableAt = SafeCast.toUint40(newRemovableAt);
    // }

    // /**
    //  * @dev Approve the provided list of addresses to initiate withdrawal on the account. Approve address(0) to allow
    //  * anyone.
    //  */
    // function approveAddressesForWithdrawal(
    //     BalanceShare storage _self,
    //     address account,
    //     address[] calldata approvedAddresses
    // ) internal {
    //     for (uint256 i = 0; i < approvedAddresses.length;) {
    //         _self._accountWithdrawalApprovals[account][approvedAddresses[i]] = true;
    //         unchecked { ++i; }
    //     }
    // }

    // /**
    //  * @dev Un-approve the provided list of addresses for initiating withdrawals on the account.
    //  */
    // function unapproveAddressesForWithdrawal(
    //     BalanceShare storage _self,
    //     address account,
    //     address[] calldata unapprovedAddresses
    // ) internal {
    //     for (uint256 i = 0; i < unapprovedAddresses.length;) {
    //         _self._accountWithdrawalApprovals[account][unapprovedAddresses[i]] = false;
    //         unchecked { ++i; }
    //     }
    // }

    // /**
    //  * @dev A function for changing the address that an account receives its shares to. This is only callable by the
    //  * account owner. A list of approved addresses for withdrawal can be provided.
    //  *
    //  * Note that by default, if the address(0) was approved (meaning anyone can process a withdrawal to the account),
    //  * then address(0) will be approved for the new account address as well.
    //  *
    //  * @param account The address for the current account share (which must be msg.sender)
    //  * @param newAccount The new address to copy the account share over to.
    //  * @param approvedAddresses A list of addresses to be approved for processing withdrawals to the account receiver.
    //  */
    // function changeAccountAddress(
    //     BalanceShare storage _self,
    //     address account,
    //     address newAccount,
    //     address[] calldata approvedAddresses
    // ) internal {
    //     if (msg.sender != account) revert Unauthorized();
    //     if (newAccount == address(0)) revert InvalidAddress(newAccount);
    //     // Copy it over
    //     _self._accounts[newAccount] = _self._accounts[account];
    //     // Zero out the old account
    //     delete _self._accounts[account];

    //     // Approve addresses
    //     approveAddressesForWithdrawal(_self, newAccount, approvedAddresses);

    //     if (_self._accountWithdrawalApprovals[account][address(0)]) {
    //         _self._accountWithdrawalApprovals[newAccount][address(0)] = true;
    //     }
    // }

    // /**
    //  * @dev The total basis points sum for all currently active account shares.
    //  * @return totalBps An integer representing the total basis points sum. 1 basis point = 0.01%
    //  */
    // function totalBps(
    //     BalanceShare storage _self
    // ) internal view returns (uint256) {
    //     uint256 length = _self._balanceChecks.length;
    //     return length > 0 ?
    //         _self._balanceChecks[length - 1].totalBps :
    //         0;
    // }

    // /**
    //  * @dev Returns the current withdrawable balance for an account share.
    //  * @return balanceAvailable The balance available for withdraw from this account.
    //  */
    // function accountBalance(
    //     BalanceShare storage _self,
    //     address account
    // ) internal view returns (uint256) {
    //     AccountShare storage accountShare = _self._accounts[account];
    //     (uint256 balanceAvailable,,) = _calculateAccountBalance(
    //         _self,
    //         accountShare,
    //         false // Show the zero balance
    //     );
    //     return balanceAvailable;
    // }

    // /**
    //  * @dev A helper function to predict the account balance with an additional "balanceIncreasedBy" parameter (assuming
    //  * the state has not been updated to match yet).
    //  * @return accountBalance Returns the predicted account balance.
    //  */
    // function predictedAccountBalance(
    //     BalanceShare storage _self,
    //     address account,
    //     uint256 balanceIncreasedBy
    // ) internal view returns (uint256) {
    //     AccountShare storage accountShare = _self._accounts[account];
    //     (uint256 balanceAvailable,,) = _calculateAccountBalance(
    //         _self,
    //         accountShare,
    //         false
    //     );
    //     (uint256 addedTotalBalance,) = _calculateBalanceShare(
    //         _self,
    //         balanceIncreasedBy,
    //         accountShare.bps
    //     );
    //     return balanceAvailable + addedTotalBalance.bps(accountShare.bps);
    // }

    // /**
    //  * @dev Returns a bool indicating whether or not the address is approved for withdrawal on the specified account.
    //  */
    // function isAddressApprovedForWithdrawal(
    //     BalanceShare storage _self,
    //     address account,
    //     address address_
    // ) internal view returns (bool) {
    //     return _self._accountWithdrawalApprovals[account][address_];
    // }

    // /**
    //  * @dev Returns the following details (in order) for the specified account:
    //  * - bps
    //  * - createdAt
    //  * - removableAt
    //  * - lastWithdrawnAt
    //  */
    // function accountDetails(
    //     BalanceShare storage _self,
    //     address account
    // ) internal view returns (uint256, uint256, uint256, uint256) {
    //     AccountShare storage accountShare = _self._accounts[account];
    //     return (
    //         accountShare.bps,
    //         accountShare.createdAt,
    //         accountShare.removableAt,
    //         accountShare.lastWithdrawnAt
    //     );
    // }

    // /**
    //  * @dev An account is considered to be finished with withdrawals when the account's "lastBalanceCheckIndex" is
    //  * greater than the account's "endIndex".
    //  *
    //  * Returns true if the account has not been initialized with any shares yet.
    //  */
    // function accountHasFinishedWithdrawals(
    //     BalanceShare storage _self,
    //     address account
    // ) internal view returns (bool) {
    //     return _accountHasFinishedWithdrawals(_self._accounts[account]);
    // }



    // /**
    //  * @dev Private function to calculate the current balance owed to the AccountShare.
    //  * @return accountBalanceOwed The balance owed to the account share.
    //  * @return lastBalanceCheckIndex The resulting lastBalanceCheckIndex for the account.
    //  * @return lastBalancePulled The resulting lastBalancePulled for the account.
    //  */
    // function _calculateAccountBalance(
    //     BalanceShare storage _self,
    //     AccountShare storage accountShare,
    //     bool revertOnWithdrawalsFinished
    // ) private view returns(
    //     uint256 accountBalanceOwed,
    //     uint256,
    //     uint256
    // ) {
    //     (
    //         uint256 bps,
    //         uint256 createdAt,
    //         uint256 endIndex,
    //         uint256 lastBalanceCheckIndex,
    //         uint256 lastBalancePulled
    //     ) = (
    //         accountShare.bps,
    //         accountShare.createdAt,
    //         accountShare.endIndex,
    //         accountShare.lastBalanceCheckIndex,
    //         accountShare.lastBalancePulled
    //     );

    //     // If account is not active or is already finished with withdrawals, return zero
    //     if (_accountHasFinishedWithdrawals(createdAt, lastBalanceCheckIndex, endIndex)) {
    //         if (revertOnWithdrawalsFinished) {
    //             revert AccountWithdrawalsFinished();
    //         }
    //         return (accountBalanceOwed, lastBalanceCheckIndex, lastBalancePulled);
    //     }

    //     uint256 latestBalanceCheckIndex = _self._balanceChecks.length - 1;

    //     // Process each balanceCheck while in range of the endIndex, summing the total balance to be paid
    //     while (lastBalanceCheckIndex <= endIndex) {
    //         BalanceCheck memory balanceCheck = _self._balanceChecks[lastBalanceCheckIndex];
    //         uint256 diff = balanceCheck.balance - lastBalancePulled;
    //         if (diff > 0 && balanceCheck.totalBps > 0) {
    //             // For each check, add (balanceCheck.balance - lastBalancePulled) * (accountBps / balanceCheck.totalBps)
    //             accountBalanceOwed += Math.mulDiv(diff, bps, balanceCheck.totalBps);
    //         }
    //         // Do not increment past the end of the balanceChecks array
    //         if (lastBalanceCheckIndex == latestBalanceCheckIndex) {
    //             // Track this balance to save to the account's storage as the lastPulledBalance
    //             unchecked {
    //                 lastBalancePulled = balanceCheck.balance;
    //             }
    //             break;
    //         }
    //         /**
    //          * @dev Notice that this increments the lastBalanceCheckIndex PAST the endIndex for an account that has had
    //          * their balance share removed at some point.
    //          *
    //          * This is the desired behavior. See the private _accountHasFinishedWithdrawals function. This considers an
    //          * account to be finished with withdrawals once the lastBalanceCheckIndex is greater than the endIndex.
    //          */
    //         unchecked {
    //             lastBalanceCheckIndex += 1;
    //             lastBalancePulled = 0;
    //         }
    //     }

    //     return (accountBalanceOwed, lastBalanceCheckIndex, lastBalancePulled);

    // }

    /// @dev Private helper to retrieve a BalanceShare for the client and balanceShareId (gas optimized)
    function _getBalanceShare(address client, uint256 balanceShareId) private pure returns (BalanceShare storage $) {
        /// @solidity memory-safe-assembly
        assembly {
            /**
             * keccak256(balanceShareId . keccak256(client . _balanceShares.slot))
             */
            mstore(0, client)
            mstore(0x20, _balanceShares.slot)
            mstore(0x20, keccak256(0, 0x40))
            mstore(0, balanceShareId)
            $.slot := keccak256(0, 0x40)
        }
    }

    function _getCurrentBalanceSumCheckpoint(
        BalanceShare storage _balanceShare
    ) private view returns (BalanceSumCheckpoint storage $) {
        /// @solidity memory-safe-assembly
        assembly {
            /**
             * keccak256(_balanceShare.balanceSumCheckpointIndex . _balanceShare.balanceSumCheckpoints.slot))
             */
            mstore(0, sload(_balanceShare.slot))
            mstore(0x20, add(_balanceShare.slot, 0x01))
            $.slot := keccak256(0, 0x40)
        }
    }

    function _getBalanceSum(
        BalanceSumCheckpoint storage _balanceSumCheckpoint,
        address asset
    ) private pure returns (BalanceSum storage $) {
        /// @solidity memory-safe-assembly
        assembly {
            /**
             * keccak256(address . _balanceSumCheckpoint.balanceSums.slot))
             */
            mstore(0, asset)
            mstore(0x20, add(_balanceSumCheckpoint.slot, 0x01))
            $.slot := keccak256(0, 0x40)
        }
    }

}