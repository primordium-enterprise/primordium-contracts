// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {BalanceSharesAccounts} from "./BalanceSharesAccounts.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract BalanceSharesWithdrawals is BalanceSharesAccounts, EIP712, Nonces {

    struct WithdrawalCheckpointCache {
        bytes32 packedValue;
        bytes32 storageSlot;
    }

    struct BalanceSumCheckpointCache {
        uint256 totalBps;
        bytes32 balanceSumsStorageSlot;
    }

    bytes32 public immutable WITHDRAW_TO_TYPEHASH = keccak256(
        "WithdrawTo(address client,uint256 balanceShareId,address account,address receiver,address[] assets,uint256 periodIndex,uint256 nonce,uint256 deadline)"
    );

    event AccountSharePeriodAssetWithdrawal(
        address indexed client,
        uint256 indexed balanceShareId,
        address indexed account,
        address asset,
        uint256 withdrawAmount,
        address receiver,
        uint256 periodIndex
    );

    error UnauthorizedForWithdrawal(address sender);
    error WithdrawInvalidSignature();
    error WithdrawExpiredSignature(uint256 deadline);
    error MissingAssets();
    error ETHTransferFailed();

    /**
     * Get the withdrawable asset balances for the provided period index.
     * @param client The client account for the balance share.
     * @param balanceShareId The uint256 identifier of the client's balance share.
     * @param account The address of the account
     * @param assets A list of ERC20 assets to get withdrawable balances for (address(0) for ETH).
     * @param periodIndex The period index to withdraw for. Call {getAccountCurrentPeriodIndex} for the current period
     * index.
     * @return withdrawableBalances A list of withdrawable balances, in the same order as the assets list.
     * @return checkpointIterations The total amount of checkpoint iterations to withdraw the full balance.
     */
    function getAccountSharePeriodWithdrawableBalances(
        address client,
        uint256 balanceShareId,
        address account,
        address[] memory assets,
        uint256 periodIndex
    ) public view returns (uint256[] memory withdrawableBalances, uint256 checkpointIterations) {
        (withdrawableBalances,,checkpointIterations) = _getAccountSharePeriodWithdrawableBalances(
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
        WithdrawalCheckpointCache[] memory withdrawalCheckpointCaches,
        uint256 checkpointIterations
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
            return (withdrawableBalances, withdrawalCheckpointCaches, checkpointIterations);
        }

        // Set the end index (which is not allowed to be greater than _balanceShare.balanceSumCheckpointIndex + 1)
        // End index is non-inclusive, so when calculating the max, we add 1 to the current index
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
        checkpointIterations = endBalanceSumIndex - startBalanceSumIndex;
        BalanceSumCheckpointCache[] memory balanceSumCheckpointCaches =
            new BalanceSumCheckpointCache[](checkpointIterations);

        /// @solidity memory-safe-assembly
        assembly {
            let _balanceSumCheckpointSlot := 0

            for { let i := 0 } lt(i, checkpointIterations) { i := add(i, 0x01) } {
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
        unchecked {
            for (uint256 i = 0; i < assetCount;) {
                address asset = assets[i];
                uint256 assetWithdrawBalance;

                // Unpack the withdrawal checkpoint cache
                WithdrawalCheckpointCache memory withdrawalCheckpointCache = withdrawalCheckpointCaches[i];
                uint256 startIndex;
                uint256 prevBalance;
                /// @solidity memory-safe-assembly
                assembly {
                    let packedWithdrawalCheckpoint := mload(withdrawalCheckpointCache)
                    startIndex := and(packedWithdrawalCheckpoint, MASK_UINT48)
                    prevBalance := shr(0x30, packedWithdrawalCheckpoint)
                }

                // Loop through cached checkpoints
                /**
                 * Skip to the cache index where this asset last withdrew from. Example:
                 * startBalanceSumIndex = 20
                 * endBalanceSumIndex = 30
                 * checkpointIterations = 30 - 20 = 10
                 *
                 * If the asset last withdrew from index 25, then skip the first five elements, starting at the sixth
                 * j = 10 - (30 - 25) = 5
                 */
                uint256 j = checkpointIterations - (endBalanceSumIndex - startIndex);
                if (j < checkpointIterations) {
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

                        if (j == checkpointIterations - 1) {
                            prevBalance = currentBalanceSum;
                            break;
                        } else {
                            prevBalance = 0;
                            ++j;
                        }
                    }

                    // Update the packed value in the WithdrawalCheckpointCache
                    /// @solidity memory-safe-assembly
                    assembly {
                        // Store the endBalanceSumIndex - 1 since end index is non-inclusive
                        mstore(withdrawalCheckpointCache, or(sub(endBalanceSumIndex, 0x01), shl(0x30, prevBalance)))
                    }
                }

                // Update the asset withdrawal balance
                withdrawableBalances[i] = assetWithdrawBalance;

                ++i;
            }
        }
    }

    function withdrawAccountSharePeriodTo(
        address client,
        uint256 balanceShareId,
        address account,
        address receiver,
        address[] memory assets,
        uint256 periodIndex
    ) public returns (uint256[] memory withdrawAmounts) {
        if (msg.sender != account) {
            revert UnauthorizedForWithdrawal(msg.sender);
        }

        withdrawAmounts = _processAcountSharePeriodWithdrawal(
            client,
            balanceShareId,
            account,
            receiver,
            assets,
            periodIndex
        );
    }

    function withdrawAccountSharePeriod(
        address client,
        uint256 balanceShareId,
        address account,
        address[] memory assets,
        uint256 periodIndex
    ) external returns (uint256[] memory) {
        return withdrawAccountSharePeriodTo(client, balanceShareId, account, account, assets, periodIndex);
    }

    function withdrawAccountSharePeriodToBySig(
        address client,
        uint256 balanceShareId,
        address account,
        address receiver,
        address[] memory assets,
        uint256 periodIndex,
        uint256 deadline,
        bytes memory signature
    ) public virtual returns (uint256[] memory withdrawAmounts) {
        if (block.timestamp > deadline) {
            revert WithdrawExpiredSignature(deadline);
        }

        // Copy the tokens content to memory and hash
        bytes32 encodedAssets;
        // @solidity memory-safe-assembly
        assembly {
            // Get the total byte length of the items (array length * 32 bytes per item)
            let byteLength := mul(mload(assets), 0x20)
            let dataStart := add(assets, 0x20)
            let dataEnd := add(dataStart, mul(mload(assets), 0x20))
            encodedAssets := keccak256(dataStart, dataEnd)
        }

        bool valid = SignatureChecker.isValidSignatureNow(
            account,
            _hashTypedDataV4(keccak256(abi.encode(
                WITHDRAW_TO_TYPEHASH,
                client,
                balanceShareId,
                account,
                receiver,
                encodedAssets,
                periodIndex,
                _useNonce(account),
                deadline
            ))),
            signature
        );

        if (!valid) {
            revert WithdrawInvalidSignature();
        }

        withdrawAmounts = _processAcountSharePeriodWithdrawal(
            client,
            balanceShareId,
            account,
            receiver,
            assets,
            periodIndex
        );
    }

    function _processAcountSharePeriodWithdrawal(
        address client,
        uint256 balanceShareId,
        address account,
        address receiver,
        address[] memory assets,
        uint256 periodIndex
    ) internal returns (uint256[] memory withdrawAmounts) {
        // Get the withdrawable balances
        (
            uint256[] memory withdrawableAmounts,
            WithdrawalCheckpointCache[] memory withdrawalCheckpointCaches,
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