// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {BSStorage} from "./BSStorage.sol";
import {BasisPoints} from "contracts/libraries/BasisPoints.sol";
import {IBalanceSharesManager} from "contracts/executor/interfaces/IBalanceSharesManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Utils} from "contracts/libraries/ERC20Utils.sol";

/**
 * @title Balance share processing functions for BalanceSharesSingleton
 * @author Ben Jett - @BCJdevelopment
 */
contract BSBalanceAllocations is BSStorage, IBalanceSharesManager {
    using ERC20Utils for IERC20;

    error BalanceShareInactive(address client, uint256 balanceShareId);
    error InvalidAllocationAmount(uint256 amountToAllocate);
    error InvalidMsgValue(uint256 expectedValue, uint256 actualValue);

    /**
     * Emitted when an asset is allocated to a balance share for the specified client and balance share ID.
     * @notice The new asset remainder will only be included if the amountAllocated is zero.
     */
    event BalanceShareAssetAllocated(
        address indexed client,
        uint256 indexed balanceShareId,
        IERC20 indexed asset,
        uint256 amountAllocated,
        uint256 newAssetRemainder
    );

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
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
     * Same as above, but uses the msg.sender as the "client" parameter.
     */
    function getBalanceShareTotalBPS(
        uint256 balanceShareId
    ) public view override returns (uint256) {
        return getBalanceShareTotalBPS(msg.sender, balanceShareId);
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
        IERC20 asset,
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
        IERC20 asset,
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
     * @return remainderIncrease A bool indicating whether or not the remainder increased as a result of this function.
     * Will return true if the remainder increased, even if the amountToAllocate is zero.
     */
    function getBalanceShareAllocationWithRemainder(
        address client,
        uint256 balanceShareId,
        IERC20 asset,
        uint256 balanceIncreasedBy
    ) public view returns (uint256 amountToAllocate, bool remainderIncrease) {
        uint256 newAssetRemainder;
        (amountToAllocate, newAssetRemainder,) = _calculateBalanceShareAllocation(
            _getBalanceShare(client, balanceShareId),
            asset,
            balanceIncreasedBy,
            true
        );
        remainderIncrease = newAssetRemainder < MAX_BPS;
    }

    /**
     * Same as {getBalanceShareAllocationWithRemainder} above, but uses the msg.sender as the "client" parameter.
     */
    function getBalanceShareAllocationWithRemainder(
        uint256 balanceShareId,
        IERC20 asset,
        uint256 balanceIncreasedBy
    ) external view override returns (uint256, bool) {
        return getBalanceShareAllocationWithRemainder(msg.sender, balanceShareId, asset, balanceIncreasedBy);
    }

    function _calculateBalanceShareAllocation(
        BalanceShare storage _balanceShare,
        IERC20 asset,
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
            } else {
                newAssetRemainder = MAX_BPS;
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
        IERC20 asset,
        uint256 amountToAllocate
    ) public payable {
        if (amountToAllocate == 0) {
            revert InvalidAllocationAmount(amountToAllocate);
        }

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

        emit BalanceShareAssetAllocated(client, balanceShareId, asset, amountToAllocate, 0);
    }

    /**
     * Same as {allocateToBalanceShare} above, but uses msg.sender as the "client" parameter.
     */
    function allocateToBalanceShare(
        uint256 balanceShareId,
        IERC20 asset,
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
        IERC20 asset,
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

            emit BalanceShareAssetAllocated(msg.sender, balanceShareId, asset, amountToAllocate, newAssetRemainder);
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
        IERC20 asset,
        uint256 amountToAllocate,
        uint256 newAssetRemainder
    ) internal {
        if (amountToAllocate == 0 && newAssetRemainder == MAX_BPS) {
            return;
        }

        BalanceSumCheckpoint storage _balanceSumCheckpoint = _currentBalanceSumCheckpoint;

        // Transfer the asset to this contract
        asset.receiveFrom(msg.sender, amountToAllocate);

        unchecked {
            BalanceSum storage _currentBalanceSum = _getBalanceSum(_balanceSumCheckpoint, asset);

            uint256 maxBalanceSum = MAX_BALANCE_SUM_BALANCE;
            uint256 maxBps = MAX_BPS;
            assembly ("memory-safe") {
                // Cache the packed BalanceSumCheckpoint
                let balanceSumCheckpointPacked := sload(_balanceSumCheckpoint.slot)

                // Check that "hasBalances" is true, or else mark it as true
                if iszero(and(shr(16, balanceSumCheckpointPacked), 0xff)) {
                    // We don't need to mask the current value, because we already know the 1 bool byte is zero
                    balanceSumCheckpointPacked := or(balanceSumCheckpointPacked, shl(16, 0x01))
                    sstore(_balanceSumCheckpoint.slot, balanceSumCheckpointPacked)
                }

                // Cache packed BalanceSum slot
                let balanceSumPacked := sload(_currentBalanceSum.slot)

                // Load current remainder (first 48 bits)
                let assetRemainder := and(balanceSumPacked, MASK_UINT48)
                // Update to new remainder if the new one is less than MAX_BPS
                if lt(newAssetRemainder, maxBps) {
                    assetRemainder := newAssetRemainder
                }

                // Load current balance (shift BalanceSum slot right by 48 bits)
                let assetBalance := shr(48, balanceSumPacked)

                // Add to the balance sum, looping to avoid overflow as needed
                for { } true { } {
                    // Set the balance increase amount (do not allow overflow of BalanceSum.balance)
                    let balanceIncrease := sub(maxBalanceSum, assetBalance)
                    if lt(amountToAllocate, balanceIncrease) {
                        balanceIncrease := amountToAllocate
                    }

                    // Add to the current balance
                    assetBalance := add(assetBalance, balanceIncrease)

                    // Update the slot cache, then store
                    balanceSumPacked := or(assetRemainder, shl(48, assetBalance))
                    sstore(_currentBalanceSum.slot, balanceSumPacked)

                    // Finished once the allocation reaches zero
                    amountToAllocate := sub(amountToAllocate, balanceIncrease)
                    if iszero(amountToAllocate) {
                        break
                    }

                    // If more to allocate, start a new balance sum checkpoint (and copy the totalBps)
                    mstore(0, add(sload(_balanceShare.slot), 0x01)) // Store incremented checkpoint index in scratch
                    sstore(_balanceShare.slot, mload(0)) // Update the checkpoint index in storage

                    // Update the storage reference to the new BalanceSumCheckpoint
                    // keccak256(_balanceShare.balanceSumCheckpointIndex . _balanceShare.balanceSumCheckpoints.slot))
                    mstore(0x20, add(_balanceShare.slot, 0x01))
                    _balanceSumCheckpoint.slot := keccak256(0, 0x40)

                    // Copy over the previous packed checkpoint
                    sstore(_balanceSumCheckpoint.slot, balanceSumCheckpointPacked)

                    // Reset the current balance to zero
                    assetBalance := 0

                    // Update the BalanceSum reference
                    // keccak256(address . _balanceSumCheckpoint.balanceSums.slot))
                    mstore(0, asset)
                    mstore(0x20, add(_balanceSumCheckpoint.slot, 0x01))
                    _currentBalanceSum.slot := keccak256(0, 0x40)
                }
            }
        }
    }
}