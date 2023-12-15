// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {BasisPoints} from "contracts/libraries/BasisPoints.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

/**
 * @title Storage layout for BalanceSharesSingleton
 * @author Ben Jett - @BCJdevelopment
 */
contract BSStorage is ERC165 {

mapping(address client => mapping(uint256 balanceShareId => BalanceShare)) internal _balanceShares;

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
        uint16 totalBps; // Tracks the totalBps among all account shares for this balance sum checkpoint
        bool hasBalances; // Will be flipped to "true" if an asset BalanceSum has been recorded in this checkpoint
        mapping(address asset => BalanceSum) balanceSums;
    }

    /**
     * @dev Storing asset remainders in the BalanceSum struct will not carry asset remainders over to a new
     * BalanceSumCheckpoint, but packing the storage with the asset balance avoids writing to an extra storage slot
     * when a new balance is processed and added to the balance sum. We optimize for the gas usage here, as new
     * checkpoints will only be written when the total BPS changes or an asset overflows, both of which are not likely
     * to be as common of events as the actual balance processing itself.
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
        uint48 initializedAtBlock;
        // Timestamp in seconds at which the account share bps can be decreased or removed by the client
        uint48 removableAt;
        // Tracks the current balance sum position for the last withdrawal per asset
        mapping(address asset => WithdrawalCheckpoint) withdrawalCheckpoints;
    }

    struct WithdrawalCheckpoint {
        uint48 currentCheckpointIndex; // The current asset balance check index for the account
        uint208 previousBalanceAtWithdrawal; // The asset balance when it was last withdrawn by the account
    }

    // HELPER CONSTANTS
    uint256 constant public MAX_BPS = BasisPoints.MAX_BPS;
    uint256 constant internal MAX_INDEX = type(uint48).max;
    uint256 constant internal MAX_BALANCE_SUM_BALANCE = type(uint208).max;

    uint256 constant internal MASK_UINT16 = 0xffff;
    uint256 constant internal MASK_UINT48 = 0xffffffffffff;

    error InvalidAccountSharePeriodIndex(uint256 providedPeriodIndex, uint256 maxAccountPeriodIndex);

    function _getBalanceShare(address client, uint256 balanceShareId) internal pure returns (BalanceShare storage $) {
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
    ) internal view returns (BalanceSumCheckpoint storage $) {
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
        IERC20 asset
    ) internal pure returns (BalanceSum storage $) {
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