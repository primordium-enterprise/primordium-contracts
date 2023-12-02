// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {BalanceSharesStorage} from "./BalanceSharesStorage.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract BalanceSharesWithdrawals is BalanceSharesStorage {

    // Helper struct to be used in memory when withdrawing
    struct BalanceSumWithdrawalCache {
        bytes32 slot;
        bytes32 packedValue;
    }

    struct BalanceSumCheckpointCache {
        uint256 totalBps;
        bytes32 baalnceSumsSlot;
    }

    error NoAssetsProvided();

    function _getAccountPeriodAssetBalances(
        BalanceShare storage _balanceShare,
        address account,
        address[] memory assets,
        uint256 periodIndex
    ) internal view returns (
        uint256[] memory withdrawBalances,
        BalanceSumWithdrawalCache[] memory balanceSumWithdrawals
    ) {
        if (assets.length == 0) {
            revert NoAssetsProvided();
        }

        withdrawBalances = new uint256[](assets.length);
        balanceSumWithdrawals = new BalanceSumWithdrawalCache[](assets.length);

        AccountSharePeriod storage _accountSharePeriod = _balanceShare.accounts[account].periods[periodIndex];

        // Unpack the struct values
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

        if (bps == 0) {
            return (withdrawBalances, balanceSumWithdrawals);
        }

        // Set the end index, keeping max index in mind
        uint256 maxEndBalanceSumIndex = _balanceShare.balanceSumCheckpointIndex + 1;
        if (maxEndBalanceSumIndex < endBalanceSumIndex) {
            endBalanceSumIndex = maxEndBalanceSumIndex;
        }

        {
            // Initialize the array of balanceSumWithdrawals with the packed values and the storage slot references
            uint256 skipToStartIndex = endBalanceSumIndex;
            for (uint256 i = 0; i < assets.length;) {
                BalanceSumWithdrawal storage _balanceSumWithdrawal =
                    _accountSharePeriod.assetBalanceSumWithdrawal[assets[i]];
                assembly {
                    // Store the address of the current asset struct in scratch space
                    mstore(0, mload(add(mul(i, 0x20), add(balanceSumWithdrawals, 0x20))))
                    // Store slot in struct
                    mstore(mload(0), _balanceSumWithdrawal.slot)
                    // Store packed value in struct
                    mstore(0x20, sload(_balanceSumWithdrawal.slot))
                    mstore(add(mload(0), 0x20), mload(0x20))

                    // Read the currentCheckpointIndex, and assign to skipToStartIndex if lower than the current value
                    mstore(0, and(mload(0x20), MASK_UINT48))
                    if lt(mload(0), skipToStartIndex) {
                        skipToStartIndex := mload(0)
                    }
                }

                unchecked { ++i; }
            }

            startBalanceSumIndex = skipToStartIndex;
        }

        // Cache the needed BalanceSumCheckpoints in memory
        uint256 checkpointCount = endBalanceSumIndex - startBalanceSumIndex;
        BalanceSumCheckpointCache[] memory checkpointCaches = new BalanceSumCheckpointCache[](checkpointCount);

        for (uint256 i = 0; i < checkpointCount;) {
            BalanceSumCheckpoint storage _balanceSumCheckpoint =
                _balanceShare.balanceSumCheckpoints[startBalanceSumIndex + i];

            assembly {
                // Store the address of the current struct in scratch space
                mstore(0, mload(add(mul(i, 0x20), add(checkpointCaches, 0x20))))
                // Store the totalBps
                mstore(mload(0), sload(_balanceSumCheckpoint.slot))
                // Store the slot for the mapping, used below to retrieve value based on asset key
                mstore(add(mload(0), 0x20), add(_balanceSumCheckpoint.slot, 0x01))
            }

            unchecked { ++i; }
        }

        // Finally, loop through each asset again (yes repetitive), calculate sum total asset balance with account bps
        for (uint256 i = 0; i < assets.length;) {
            address asset = assets[i];
            uint256 assetWithdrawBalance;

            bytes32 packedBalanceSumWithdrawal = balanceSumWithdrawals[i].packedValue;

            uint256 startIndex;
            uint256 prevBalance;
            assembly {
                startIndex := and(packedBalanceSumWithdrawal, MASK_UINT48)
                prevBalance := shr(0x30, packedBalanceSumWithdrawal)
            }

            // Loop through cached checkpoints, starting at this asset's starting point
            uint256 j = endBalanceSumIndex - startIndex;
            while (true) {
                BalanceSumCheckpointCache memory checkpoint = checkpointCaches[j];
                uint256 currentBalanceSum;
                assembly {
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

            // Update the BalanceSumWithdrawalCache
            assembly {
                packedBalanceSumWithdrawal := or(endBalanceSumIndex, shl(0x30, prevBalance))
            }
            balanceSumWithdrawals[i].packedValue = packedBalanceSumWithdrawal;

            // Update the asset withdrawal balance
            withdrawBalances[i] = assetWithdrawBalance;

            unchecked { ++i; }
        }
    }
}