// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {BalanceSharesStorage} from "./BalanceSharesStorage.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract BalanceSharesWithdrawals is BalanceSharesStorage {

    struct WithdrawalCheckpointCache {
        bytes32 storageSlot;
        bytes32 packedValue;
    }

    struct BalanceSumCheckpointCache {
        uint256 totalBps;
        bytes32 balanceSumsStorageSlot;
    }

    error MissingAssets();

    function _getAccountPeriodWithdrawableBalances(
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

        withdrawableBalances = new uint256[](assetCount);
        withdrawalCheckpointCaches = new WithdrawalCheckpointCache[](assetCount);

        AccountSharePeriod storage _accountSharePeriod = _balanceShare.accounts[account].periods[periodIndex];

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

        // Set the end index (which should not be greater than _balanceShare.balanceSumCheckpointIndex + 1)
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0, add(sload(_balanceShare.slot), 0x01))
            if lt(mload(0), endBalanceSumIndex) {
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
                mstore(0, mload(add(mul(i, 0x20), add(withdrawalCheckpointCaches, 0x20))))
                // set storageSlot in struct
                mstore(mload(0), _withdrawalCheckpointSlot)
                // set packedValue in struct
                mstore(0x20, sload(_withdrawalCheckpointSlot))
                mstore(add(mload(0), 0x20), mload(0x20))

                // Read the currentCheckpointIndex, and assign to skipToStartIndex if lower than the current value
                let currentCheckpointIndex := and(mload(0x20), MASK_UINT48)
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
                let packedBalanceSumWithdrawal := mload(add(withdrawalCheckpointCache, 0x20))
                startIndex := and(packedBalanceSumWithdrawal, MASK_UINT48)
                prevBalance := shr(0x30, packedBalanceSumWithdrawal)
            }

            // Loop through cached checkpoints, starting at this asset's starting point
            uint256 j = endBalanceSumIndex - startIndex;
            while (true) {
                BalanceSumCheckpointCache memory checkpoint = balanceSumCheckpointCaches[j];
                uint256 currentBalanceSum;
                assembly {
                    // Load the current balance sum
                    mstore(0, asset)
                    mstore(0x20, mload(add(checkpoint, 0x20)))
                    currentBalanceSum := sload(keccak256(0, 0x40))
                }

                uint256 diff = currentBalanceSum - prevBalance;
                if (diff > 0) {
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
            assembly {
                mstore(add(withdrawalCheckpointCache, 0x20), or(endBalanceSumIndex, shl(0x30, prevBalance)))
            }

            // Update the asset withdrawal balance
            withdrawableBalances[i] = assetWithdrawBalance;

            unchecked { ++i; }
        }
    }
}