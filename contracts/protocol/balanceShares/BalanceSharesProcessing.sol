// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {BalanceSharesStorage} from "./BalanceSharesStorage.sol";
import {BasisPoints} from "contracts/libraries/BasisPoints.sol";
import {IBalanceSharesManager} from "contracts/executor/interfaces/IBalanceSharesManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Balance share processing functions for BalanceSharesSingleton
 * @author Ben Jett - @BCJdevelopment
 */
contract BalanceSharesProcessing is BalanceSharesStorage, IBalanceSharesManager {

    error BalanceShareInactive(address client, uint256 balanceShareId);
    error InvalidMsgValue(uint256 expectedValue, uint256 actualValue);

    event BalanceShareAssetAllocated(
        address indexed client,
        uint256 indexed balanceShareId,
        address indexed asset,
        uint256 amountAllocated
    );

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return
            interfaceId == type(IBalanceSharesManager).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * Returns the current total BPS for the given balance share (the combined BPS share of all active account shares).
     * @param client The client account for the balance share.
     * @param balanceShareId The uint256 identifier of the client's balance share.
     * @return totalBps The current total BPS across all account shares for this balance share.
     */
    function getBalanceShareTotalBPS(
        address client,
        uint256 balanceShareId
    ) public view returns (uint256 totalBps) {
        totalBps = _getCurrentBalanceSumCheckpoint(
            _getBalanceShare(client, balanceShareId)
        ).totalBps;
    }

    /**
     * For the provided balance share and asset, returns the amount of the asset to send to this contract for the
     * provided amount that the balance increased by (as a function of the balance share's total BPS).
     * @param client The client account for the balance share.
     * @param balanceShareId The uint256 identifier of the client's balance share.
     * @param asset The ERC20 asset to process the balance share for (address(0) for ETH).
     * @param balanceIncreasedBy The amount that the total balance share increased by.
     * @return amountToAllocate The amount of the asset that should be allocated to the balance share. Mathematically:
     * amountToAllocate = balanceIncreasedBy * totalBps / 10_000
     */
    function getBalanceShareAllocation(
        address client,
        uint256 balanceShareId,
        address asset,
        uint256 balanceIncreasedBy
    ) public view returns (uint256 amountToAllocate) {
        (amountToAllocate,,) = _calculateBalanceShareAllocation(
            _getBalanceShare(client, balanceShareId),
            asset,
            balanceIncreasedBy,
            false
        );
    }

    /**
     * Same as {getBalanceShareAllocation} above, but uses the msg.sender as the "client" parameter.
     */
    function getBalanceShareAllocation(
        uint256 balanceShareId,
        address asset,
        uint256 balanceIncreasedBy
    ) external view override returns (uint256) {
        return getBalanceShareAllocation(msg.sender, balanceShareId, asset, balanceIncreasedBy);
    }

    /**
     * Same as {getBalanceShareAllocation}, but also includes integer remainders from the previous balance allocation.
     * This is useful for calculations with small balance increase amounts relative to the max BPS (10,000). Use this
     * in conjunction with {allocateToBalanceShareWithRemainder} to track the remainders over each allocation.
     * @param client The client account for the balance share.
     * @param balanceShareId The uint256 identifier of the client's balance share.
     * @param asset The ERC20 asset to process the balance share for (address(0) for ETH).
     * @param balanceIncreasedBy The amount that the total balance share increased by.
     * @return amountToAllocate The amount of the asset that should be allocated to the balance share. Mathematically:
     * amountToAllocate = (balanceIncreasedBy + previousAssetRemainder) * totalBps / 10_000
     */
    function getBalanceShareAllocationWithRemainder(
        address client,
        uint256 balanceShareId,
        address asset,
        uint256 balanceIncreasedBy
    ) public view returns (uint256 amountToAllocate) {
        (amountToAllocate,,) = _calculateBalanceShareAllocation(
            _getBalanceShare(client, balanceShareId),
            asset,
            balanceIncreasedBy,
            true
        );
    }

    /**
     * Same as {getBalanceShareAllocationWithRemainder} above, but uses the msg.sender as the "client" parameter.
     */
    function getBalanceShareAllocationWithRemainder(
        uint256 balanceShareId,
        address asset,
        uint256 balanceIncreasedBy
    ) external view override returns (uint256) {
        return getBalanceShareAllocationWithRemainder(msg.sender, balanceShareId, asset, balanceIncreasedBy);
    }

    function _calculateBalanceShareAllocation(
        BalanceShare storage _balanceShare,
        address asset,
        uint256 balanceIncreasedBy,
        bool useRemainder
    ) internal view returns (
        uint256 amountToAllocate,
        uint256 newAssetRemainder,
        BalanceSumCheckpoint storage _currentBalanceSumCheckpoint
    ) {
        _currentBalanceSumCheckpoint = _getCurrentBalanceSumCheckpoint(_balanceShare);

        uint256 totalBps = _currentBalanceSumCheckpoint.totalBps;
        if (totalBps > 0) {
            if (useRemainder) {
                uint256 currentAssetRemainder = _getBalanceSum(_currentBalanceSumCheckpoint, asset).remainder;
                balanceIncreasedBy += currentAssetRemainder;
                newAssetRemainder = BasisPoints.bpsMulmod(balanceIncreasedBy, totalBps);
            }

            amountToAllocate = BasisPoints.bps(balanceIncreasedBy, totalBps);
        }
    }

    /**
     * Transfers the specified amount to allocate of the given ERC20 asset from the msg.sender to this contract to be
     * split amongst the account shares for this balance share ID.
     * @param client The client account for the balance share.
     * @param balanceShareId The uint256 identifier of the client's balance share.
     * @param asset The ERC20 asset to process the balance share for (address(0) for ETH).
     * @param amountToAllocate The amount of the asset to transfer. This must equal the msg.value for asset address(0),
     * otherwise this contract must be approved to transfer at least this amount for the ERC20 asset.
     */
    function allocateToBalanceShare(
        address client,
        uint256 balanceShareId,
        address asset,
        uint256 amountToAllocate
    ) public payable {
        BalanceShare storage _balanceShare = _getBalanceShare(client, balanceShareId);
        BalanceSumCheckpoint storage _currentBalanceSumCheckpoint = _getCurrentBalanceSumCheckpoint(_balanceShare);

        // Check that the balance share is active
        if (_currentBalanceSumCheckpoint.totalBps == 0) {
            revert BalanceShareInactive(client, balanceShareId);
        }

        // Add the amount to the share (use MAX_BPS for remainder to signal no change)
        _addAssetToBalanceShare(
            _balanceShare,
            _getCurrentBalanceSumCheckpoint(_balanceShare),
            asset,
            amountToAllocate,
            MAX_BPS
        );

        emit BalanceShareAssetAllocated(client, balanceShareId, asset, amountToAllocate);
    }

    /**
     * Same as {allocateToBalanceShare} above, but uses msg.sender as the "client" parameter.
     */
    function allocateToBalanceShare(
        uint256 balanceShareId,
        address asset,
        uint256 amountToAllocate
    ) external payable override {
        allocateToBalanceShare(msg.sender, balanceShareId, asset, amountToAllocate);
    }

    /**
     * Calculates the amount to allocate using the provided amount the balance increased by, adding in the integer
     * remainder from the last balance allocation, and transfers the amount to allocate to this contract. Tracks the
     * resulting remainder for the next function call as well.
     * @notice The msg.sender is used as the client for this function, meaning only the client owner of a balance share
     * can process balance increases with the remainder included. This is to prevent an attack vector where outside
     * parties increment the remainder right up to the threshold.
     * @dev Intended to be used in conjunction with the {getBalanceShareAllocationWithRemainder} function.
     * @param balanceShareId The uint256 identifier of the client's balance share.
     * @param asset The ERC20 asset to process the balance share for (address(0) for ETH).
     * @param balanceIncreasedBy The amount of the asset to transfer. This must equal the msg.value for asset of
     * address(0), otherwise this contract must be approved to transfer at least this amount for the ERC20 asset.
     */
    function allocateToBalanceShareWithRemainder(
        uint256 balanceShareId,
        address asset,
        uint256 balanceIncreasedBy
    ) public payable {
        if (balanceIncreasedBy > 0) {
            BalanceShare storage _balanceShare = _getBalanceShare(msg.sender, balanceShareId);

            // Calculate the amount to allocate and asset remainder internally
            (
                uint256 amountToAllocate,
                uint256 newAssetRemainder,
                BalanceSumCheckpoint storage _currentBalanceSumCheckpoint
            ) = _calculateBalanceShareAllocation(_balanceShare, asset, balanceIncreasedBy, true);

            _addAssetToBalanceShare(
                _balanceShare,
                _currentBalanceSumCheckpoint,
                asset,
                amountToAllocate,
                newAssetRemainder
            );

            emit BalanceShareAssetAllocated(msg.sender, balanceShareId, asset, amountToAllocate);
        }
    }

    /**
     * @dev Helper function that adds the provided asset amount to the balance sum checkpoint. Transfers the
     * amountToAllocate of the ERC20 asset from msg.sender to this contract (or checks that msg.value is equal to the
     * amountToAllocate for an address(0) asset). Also updates the asset remainder unless newAssetRemainder is equal to
     * the MAX_BPS.
     * @notice This function assumes the provided _currentBalanceSumCheckpoint is the CURRENT checkpoint (at the current
     * balanceSumCheckpointIndex).
     */
    function _addAssetToBalanceShare(
        BalanceShare storage _balanceShare,
        BalanceSumCheckpoint storage _currentBalanceSumCheckpoint,
        address asset,
        uint256 amountToAllocate,
        uint256 newAssetRemainder
    ) internal {
        BalanceSumCheckpoint storage _balanceSumCheckpoint = _currentBalanceSumCheckpoint;

        // Transfer the asset to this contract
        if (asset == address(0)) {
            // Validate the msg.value
            if (amountToAllocate != msg.value) {
                revert InvalidMsgValue(amountToAllocate, msg.value);
            }
        } else {
            // No msg.value allowed for ERC20 transfer
            if (msg.value > 0) {
                revert InvalidMsgValue(0, msg.value);
            }
            // Only need to call transfer if the amount is greater than zero
            if (amountToAllocate > 0) {
                SafeERC20.safeTransferFrom(IERC20(asset), msg.sender, address(this), amountToAllocate);
            }
        }

        unchecked {
            BalanceSum storage _currentBalanceSum = _getBalanceSum(_balanceSumCheckpoint, asset);

            // TODO: Make the whole while loop in assembly

            // uint256 maxBalanceSum = MAX_BALANCE_SUM_BALANCE;
            // uint256 maxBps = MAX_BPS;
            // /// @solidity memory-safe-assembly
            // assembly {
            //     // Cache current packed BalanceSum slot to memory
            //     let balanceSumPacked := sload(_currentBalanceSum.slot)
            //     // Load current remainder (first 48 bits)
            //     let assetRemainder := and(balanceSumPacked, MASK_UINT48)
            //     // Update to new remainder if the new one is less than MAX_BPS
            //     if lt(newAssetRemainder, maxBps) {
            //         assetRemainder := newAssetRemainder
            //     }
            //     // Load current balance (shift BalanceSum slot right by 48 bits)
            //     let assetBalance := shr(0x30, balanceSumPacked)

            //     for { } true { } {
            //         // Set the balance increase amount in scratch space (do not allow overflow of BalanceSum.balance)
            //         mstore(0, sub(maxBalanceSum, assetBalance))
            //         if lt(amountToAllocate, mload(0)) {
            //             mstore(0, amountToAllocate)
            //         }

            //         // Add to the current balance
            //         assetBalance := add(assetBalance, mload(0))

            //         // Update the slot cache in memory, then store
            //         balanceSumPacked := or(shl(0x30, assetBalance), assetRemainder)
            //         sstore(_currentBalanceSum.slot, balanceSumPacked)

            //         // Finished once the allocation reaches zero
            //         amountToAllocate := sub(amountToAllocate, mload(0))
            //         if eq(amountToAllocate, 0) {
            //             break
            //         }

            //         // If more to allocate, increment the balance sum checkpoint index (copy the totalBps)
            //         let totalBps := sload(_balanceSumCheckpoint.slot)
            //         // Store incremented checkpoint index in scratch space and update in storage
            //         mstore(0, add(sload(_balanceShare.slot), 0x01))
            //         sstore(_balanceShare.slot, mload(0))
            //         // Set the new storage reference for the BalanceSumCheckpoint
            //         // keccak256(_balanceShare.balanceSumCheckpointIndex . _balanceShare.balanceSumCheckpoints.slot))
            //         mstore(0x20, add(_balanceShare.slot, 0x01))
            //         _balanceSumCheckpoint.slot := keccak256(0, 0x40)
            //         // Copy over the totalBps
            //         sstore(_balanceSumCheckpoint.slot, totalBps)

            //         // Reset the current balance to zero in memory, update the BalanceSum reference
            //         // keccak256(address . _balanceSumCheckpoint.balanceSums.slot))
            //         assetBalance := 0
            //         mstore(0, asset)
            //         mstore(0x20, add(_balanceSumCheckpoint.slot, 0x01))
            //         _currentBalanceSum.slot := keccak256(0, 0x40)
            //     }
            // }

            uint256 assetRemainder = _currentBalanceSum.remainder;
            uint256 assetBalance = _currentBalanceSum.balance;
            if (newAssetRemainder < MAX_BPS) {
                assetRemainder = newAssetRemainder;
            }

            while (true) {
                // For each checkpoint, the balance cannot exceed MAX_BALANCE_SUM_BALANCE
                uint256 balanceIncrease = MAX_BALANCE_SUM_BALANCE - assetBalance;
                if (amountToAllocate < balanceIncrease) {
                    balanceIncrease = amountToAllocate;
                }
                assetBalance += balanceIncrease;
                assembly {
                    // Store the packed remainder + balance (shift the assetBalance left by 48 bits)
                    sstore(_currentBalanceSum.slot, or(assetRemainder, shl(0x30, assetBalance)))
                }

                // Finished once the allocation reaches zero
                amountToAllocate -= balanceIncrease;
                if (amountToAllocate == 0) {
                    break;
                }

                // Increment the checkpoint index, update the BalanceSumCheckpoint reference (copy the totalBps)
                uint256 totalBps = _balanceSumCheckpoint.totalBps;
                _balanceSumCheckpoint =
                    _balanceShare.balanceSumCheckpoints[++_balanceShare.balanceSumCheckpointIndex];
                _balanceSumCheckpoint.totalBps = totalBps;
                // Reset currentBalance to zero
                assetBalance = 0;
                // Update the BalanceSum reference
                _currentBalanceSum = _getBalanceSum(_balanceSumCheckpoint, asset);
            }
        }
    }

}