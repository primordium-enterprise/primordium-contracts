// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {BalanceSharesStorage} from "./BalanceSharesStorage.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BalanceSharesWithdrawals is BalanceSharesStorage {

    struct WithdrawalCheckpointCache {
        bytes32 packedValue;
        bytes32 storageSlot;
    }

    struct BalanceSumCheckpointCache {
        uint256 totalBps;
        bytes32 balanceSumsStorageSlot;
    }

    event AccountSharePeriodAssetWithdrawal(
        address indexed client,
        uint256 indexed balanceShareId,
        address indexed account,
        address asset,
        uint256 withdrawAmount,
        address receiver,
        uint256 periodIndex
    );

    error InvalidAccountSharePeriodIndex(uint256 providedPeriodIndex, uint256 maxAccountPeriodIndex);
    error MissingAssets();
    error ETHTransferFailed();

    function getAccountSharePeriodWithdrawableBalances(
        address client,
        uint256 balanceShareId,
        address account,
        address[] memory assets,
        uint256 periodIndex
    ) public view returns (uint256[] memory withdrawableBalances) {
        (withdrawableBalances,) = _getAccountSharePeriodWithdrawableBalances(
            _getBalanceShare(client, balanceShareId),
            account,
            assets,
            periodIndex
        );
    }

    function _getAccountSharePeriodWithdrawableBalances(
        BalanceShare storage _balanceShare,
        address account,
        address[] memory assets,
        uint256 periodIndex
    ) internal view returns (
        uint256[] memory withdrawableBalances,
        WithdrawalCheckpointCache[] memory withdrawalCheckpointCaches
    ) {
        uint256 assetCount = assets.length;
        if (assetCount == 0) {
            revert MissingAssets();
        }

        AccountShare storage _accountShare = _balanceShare.accounts[account];
        {
            uint256 maxPeriodIndex = _accountShare.periodIndex;
            if (periodIndex > maxPeriodIndex) {
                revert InvalidAccountSharePeriodIndex(periodIndex, maxPeriodIndex);
            }
        }

        AccountSharePeriod storage _accountSharePeriod = _accountShare.periods[periodIndex];

        withdrawableBalances = new uint256[](assetCount);
        withdrawalCheckpointCaches = new WithdrawalCheckpointCache[](assetCount);

        // Unpack the AccountSharePeriod struct values
        uint256 bps;
        uint256 startBalanceSumIndex;
        uint256 endBalanceSumIndex;
        assembly {
            mstore(0, sload(_accountSharePeriod.slot))
            // bps is first 16 bits
            bps := and(mload(0), MASK_UINT16)
            // startIndex - shift right 16 bits, mask 48 bits
            startBalanceSumIndex := and(shr(0x10, mload(0)), MASK_UINT48)
            // endIndex - shift right 16 + 48 bits, mask 48 bits
            endBalanceSumIndex := and(shr(0x40, mload(0)), MASK_UINT48)
        }

        // Zero bps, just return zero values
        if (bps == 0) {
            return (withdrawableBalances, withdrawalCheckpointCaches);
        }

        // Set the end index (which is not allowed to be greater than _balanceShare.balanceSumCheckpointIndex + 1)
        /// @solidity memory-safe-assembly
        assembly {
            let maxBalanceSumIndex := add(sload(_balanceShare.slot), 0x01)
            if lt(maxBalanceSumIndex, endBalanceSumIndex) {
                endBalanceSumIndex := mload(0)
            }
        }


        // Initialize the array of withdrawalCheckpointCaches with the packed values and the storage slot references
        /// @solidity memory-safe-assembly
        assembly {
            let skipToStartIndex := endBalanceSumIndex
            let _withdrawalCheckpointSlot := 0

            for { let i := 0 } lt(i, assetCount) { i := add(i, 0x01) } {
                // Get the mapping slot for the WithdrawalCheckpoint first
                mstore(0, mload(add(mul(i, 0x20), add(assets, 0x20))))
                mstore(0x20, add(_accountSharePeriod.slot, 0x01))
                _withdrawalCheckpointSlot := keccak256(0, 0x40)

                // Store the address of the current withdrawalCheckpointCache struct in scratch space
                let cache := mload(add(mul(i, 0x20), add(withdrawalCheckpointCaches, 0x20)))
                // set packedValue in cache
                mstore(cache, sload(_withdrawalCheckpointSlot))
                // set storageSlot in cache
                mstore(add(cache, 0x20), _withdrawalCheckpointSlot)

                // Read the currentCheckpointIndex, and assign to skipToStartIndex if lower than the current value
                let currentCheckpointIndex := and(mload(cache), MASK_UINT48)
                if lt(currentCheckpointIndex, skipToStartIndex) {
                    skipToStartIndex := currentCheckpointIndex
                }
            }

            startBalanceSumIndex := skipToStartIndex
        }

        // Cache the BalanceSumCheckpoints in memory that will be used for each asset
        uint256 checkpointCount = endBalanceSumIndex - startBalanceSumIndex;
        BalanceSumCheckpointCache[] memory balanceSumCheckpointCaches =
            new BalanceSumCheckpointCache[](checkpointCount);

        /// @solidity memory-safe-assembly
        assembly {
            let _balanceSumCheckpointSlot := 0

            for { let i := 0 } lt(i, checkpointCount) { i := add(i, 0x01) } {
                // Get the mapping slot for the BalanceSumCheckpoint first
                mstore(0, add(startBalanceSumIndex, i))
                mstore(0x20, add(_balanceShare.slot, 0x01))
                _balanceSumCheckpointSlot := keccak256(0, 0x40)

                // Pointer to the address of the current struct in scratch space
                let cache := mload(add(mul(i, 0x20), add(balanceSumCheckpointCaches, 0x20)))
                // cache the totalBps
                mstore(cache, sload(_balanceSumCheckpointSlot))
                // cache the slot for the mapping, used below to retrieve value based on asset key
                mstore(add(cache, 0x20), add(_balanceSumCheckpointSlot, 0x01))
            }
        }

        // Loop through assets again (ouch), total the withdrawable asset balance across each BalanceSumCheckpointCache
        for (uint256 i = 0; i < assetCount;) {
            address asset = assets[i];
            uint256 assetWithdrawBalance;

            // Unpack the withdrawal checkpoint cache
            WithdrawalCheckpointCache memory withdrawalCheckpointCache = withdrawalCheckpointCaches[i];
            uint256 startIndex;
            uint256 prevBalance;
            /// @solidity memory-safe-assembly
            assembly {
                let packedBalanceSumWithdrawal := mload(withdrawalCheckpointCache)
                startIndex := and(packedBalanceSumWithdrawal, MASK_UINT48)
                prevBalance := shr(0x30, packedBalanceSumWithdrawal)
            }

            // Loop through cached checkpoints, starting at this asset's starting point
            uint256 j = checkpointCount - endBalanceSumIndex - startIndex;
            if (j < checkpointCount) {
                while (true) {
                    BalanceSumCheckpointCache memory checkpoint = balanceSumCheckpointCaches[j];
                    uint256 currentBalanceSum;
                    /// @solidity memory-safe-assembly
                    assembly {
                        // Load the current balance sum
                        mstore(0, asset)
                        mstore(0x20, mload(add(checkpoint, 0x20)))
                        currentBalanceSum := sload(keccak256(0, 0x40))
                    }

                    uint256 diff = currentBalanceSum - prevBalance;
                    if (diff > 0 && checkpoint.totalBps > 0) {
                        assetWithdrawBalance += Math.mulDiv(diff, bps, checkpoint.totalBps);
                    }

                    if (j == checkpointCount - 1) {
                        prevBalance = currentBalanceSum;
                        break;
                    } else {
                        prevBalance = 0;
                        unchecked { ++j; }
                    }
                }

                // Update the packed value in the WithdrawalCheckpointCache
                /// @solidity memory-safe-assembly
                assembly {
                    mstore(withdrawalCheckpointCache, or(endBalanceSumIndex, shl(0x30, prevBalance)))
                }
            }

            // Update the asset withdrawal balance
            withdrawableBalances[i] = assetWithdrawBalance;

            unchecked { ++i; }
        }
    }

    function _processAcountSharePeriodWithdrawal(
        address client,
        uint256 balanceShareId,
        address account,
        address[] memory assets,
        uint256 periodIndex,
        address receiver
    ) internal returns (uint256[] memory withdrawAmounts) {
        // Get the withdrawable balances
        (
            uint256[] memory withdrawableAmounts,
            WithdrawalCheckpointCache[] memory withdrawalCheckpointCaches
        ) = _getAccountSharePeriodWithdrawableBalances(
            _getBalanceShare(client, balanceShareId),
            account,
            assets,
            periodIndex
        );

        // Transfer the assets, and write the WithdrawalCheckpointCache updates to storage
        uint256 length = assets.length;
        for (uint256 i = 0; i < length;) {
            // Write the withdrawal storage update for the asset
            /// @solidity memory-safe-assembly
            assembly {
                let cache := mload(add(mul(i, 0x20), add(withdrawalCheckpointCaches, 0x20)))
                sstore(mload(add(cache, 0x20)), mload(cache))
            }

            // Only need to transfer for amount > 0
            if (withdrawableAmounts[i] > 0) {

                // Transfer the asset
                if (assets[i] == address(0)) {
                    (bool success,) = receiver.call{value: withdrawableAmounts[i]}("");
                    if (!success) {
                        revert ETHTransferFailed();
                    }
                } else {
                    SafeERC20.safeTransfer(IERC20(assets[i]), receiver, withdrawableAmounts[i]);
                }

                // Emit withdrawal event
                emit AccountSharePeriodAssetWithdrawal(
                    client,
                    balanceShareId,
                    account,
                    assets[i],
                    withdrawableAmounts[i],
                    receiver,
                    periodIndex
                );
            }

            unchecked { ++i; }
        }

        // Return the amounts withdrawn
        withdrawAmounts = withdrawableAmounts;
    }
}