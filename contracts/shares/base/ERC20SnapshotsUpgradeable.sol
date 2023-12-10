// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/ERC20.sol)

pragma solidity ^0.8.20;

import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC165Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {IERC20Snapshots} from "../interfaces/IERC20Snapshots.sol";
import {SnapshotCheckpoints} from "contracts/libraries/SnapshotCheckpoints.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title Allows for creating historical ERC20 balance snapshots with the IERC6372 clock mode.
 * @author Ben Jett - @BCJdevelopment
 *
 * @dev Implementation of the OpenZeppelin {ERC20} module with {ERC20Permit} and the IERC6372 clock mode, but uses
 * snapshot checkpoints to keep historical track of account balance's at the time of each created snapshot.
 *
 * @notice This contract only optimizes balance checkpoints between snapshots. The total supply checkpoints will still
 * write a new checkpoint on every mint/burn, regardless of snapshot status, to ensure compatibility with the
 * {ERC20VotesUpgradeable} that inherits from this contract.
 *
 * Maintains EIP7201 storage namespacing for upgradeability.
 */
abstract contract ERC20SnapshotsUpgradeable is
    ContextUpgradeable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    ERC165Upgradeable,
    IERC20Snapshots
{
    using SafeCast for uint256;
    using SnapshotCheckpoints for SnapshotCheckpoints.Trace208;

    /// @custom:storage-location erc7201:ERC20Snapshots.Storage
    struct ERC20SnapshotsStorage {
        uint48 _lastSnapshotClock;
        uint208 _lastSnapshotId;
        mapping(uint256 snapshotId => uint256 snapshotClock) _snapshotClocks;

        SnapshotCheckpoints.Trace208 _totalSupplyCheckpoints;
        mapping(address => SnapshotCheckpoints.Trace208) _balanceCheckpoints;
    }

    bytes32 private immutable ERC20_SNAPSHOTS_STORAGE =
        keccak256(abi.encode(uint256(keccak256("ERC20Snapshots.Storage")) - 1)) & ~bytes32(uint256(0xff));

    function _getERC20SnapshotsStorage() internal view returns (ERC20SnapshotsStorage storage $) {
        bytes32 slot = ERC20_SNAPSHOTS_STORAGE;
        assembly {
            $.slot := slot
        }
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IERC20).interfaceId ||
            interfaceId == type(IERC20Metadata).interfaceId ||
            interfaceId == type(IERC20Permit).interfaceId ||
            interfaceId == type(IERC20Snapshots).interfaceId ||
            interfaceId == type(IERC6372).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Clock used for flagging checkpoints. Defaults to block numbers, but can be overridden to implement timestamp
     * based checkpoints.
     */
    function clock() public view virtual override returns (uint48) {
        return uint48(block.number);
    }

    /**
     * @dev Description of the clock
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view virtual override returns (string memory) {
        // Check that the clock was not modified
        // solhint-disable-next-line reason-string, custom-errors
        if (clock() != block.number) revert ERC6372InconsistentClock();
        return "mode=blocknumber&from=default";
    }

    /// @inheritdoc IERC20Snapshots
    function getLastSnapshotId() public view virtual override returns (uint256 lastSnapshotId) {
        lastSnapshotId = _getERC20SnapshotsStorage()._lastSnapshotId;
    }

    /// @inheritdoc IERC20Snapshots
    function getSnapshotClock(uint256 snapshotId) public view virtual override returns (uint256 snapshotClock) {
        ERC20SnapshotsStorage storage $ = _getERC20SnapshotsStorage();
        _checkSnapshotId($, snapshotId);
        snapshotClock = $._snapshotClocks[snapshotId];
    }

    /// @inheritdoc IERC20
    function totalSupply() public view virtual override(IERC20, ERC20Upgradeable) returns (uint256) {
        ERC20SnapshotsStorage storage $ = _getERC20SnapshotsStorage();
        return $._totalSupplyCheckpoints.latest();
    }

     /// @inheritdoc IERC20Snapshots
    function getTotalSupplyAtSnapshot(
        uint256 snapshotId
    ) public view virtual override returns (uint256 totalSupplyAtSnapshot) {
        ERC20SnapshotsStorage storage $ = _getERC20SnapshotsStorage();

        // Optimize for most recent snapshot ID
        (uint256 lastSnapshotId, uint256 snapshotClock) = _checkSnapshotId($, snapshotId);
        if (snapshotId != lastSnapshotId) {
            snapshotClock = $._snapshotClocks[snapshotId];
        }

        totalSupplyAtSnapshot = $._totalSupplyCheckpoints.upperLookupRecent(uint48(snapshotClock));
    }

    /// @inheritdoc IERC20Snapshots
    function maxSupply() public view virtual override returns (uint256) {
        return type(uint208).max;
    }

    /// @inheritdoc IERC20
    function balanceOf(address account) public view virtual override(IERC20, ERC20Upgradeable) returns (uint256) {
        ERC20SnapshotsStorage storage $ = _getERC20SnapshotsStorage();
        return uint256($._balanceCheckpoints[account].latest());
    }

    /// @inheritdoc IERC20Snapshots
    function getBalanceAtSnapshot(
        address account,
        uint256 snapshotId
    ) public view virtual override returns (uint256 balanceAtSnapshot) {
        ERC20SnapshotsStorage storage $ = _getERC20SnapshotsStorage();

        // Optimize for most recent snapshot ID
        (uint256 lastSnapshotId, uint256 snapshotClock) = _checkSnapshotId($, snapshotId);
        if (snapshotId != lastSnapshotId) {
            snapshotClock = $._snapshotClocks[snapshotId];
        }

        return $._balanceCheckpoints[account].upperLookupRecent(uint8(snapshotClock));
    }

    /**
     * @dev Internal method for creating a new snapshot. Inheriting contract should implement an external method as
     * needed for creating new snapshots.
     *
     * Snapshots should NOT be created for future clock values, or else the gas optimizations of snapshots will be
     * bypassed until the future snapshot clock value passes.
     */
    function _createSnapshot() internal virtual returns (uint256 newSnapshotId) {
        ERC20SnapshotsStorage storage $ = _getERC20SnapshotsStorage();

        uint256 currentClock = clock();

        uint256 lastSnapshotClock = $._lastSnapshotClock;
        uint256 lastSnapshotId = $._lastSnapshotId;

        // A safety check, to ensure that no snapshot has already been scheduled in the future (which should not happen)
        if (lastSnapshotClock > currentClock) {
            revert ERC20SnapshotAlreadyScheduled();
        // If lastSnapshotClock is equal to currentClock, then just return the current ID.
        } else if (lastSnapshotClock == currentClock) {
            return lastSnapshotId;
        }

        // Increment the snapshotId
        newSnapshotId = lastSnapshotId + 1;

        // Set the clock value, and update the cache with the new ID and clock
        $._snapshotClocks[newSnapshotId] = currentClock;
        $._lastSnapshotClock = uint48(currentClock);
        $._lastSnapshotId = SafeCast.toUint208(newSnapshotId);

        emit SnapshotCreated(newSnapshotId, currentClock);
    }

    /**
     * @inheritdoc ERC20Upgradeable
     * @dev This function is modified to follow the exact same logic as the _update function in the original
     * ERC20Upgradeable contract, but using snapshot checkpoints for balances and total supply.
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        ERC20SnapshotsStorage storage $ = _getERC20SnapshotsStorage();

        // Cache the last snapshot clock value
        uint48 currentClock = clock();
        uint48 lastSnapshotClock = $._lastSnapshotClock;

        if (from == address(0)) {
            // For mint, increase the total supply, but not past the maxSupply
            // Must check for overflow on total supply update to protect the rest of the unchecked math
            // No snapshot optimization for totalSupply (for ERC20Votes)
            (,uint256 newTotalSupply) = $._totalSupplyCheckpoints.push(currentClock, _add, value);

            // Check that the totalSupply has not exceeded the max supply
            uint256 currentMaxSupply = maxSupply();
            if (newTotalSupply > currentMaxSupply) {
                revert ERC20MaxSupplyOverflow(currentMaxSupply, newTotalSupply);
            }
        } else {
            uint256 fromBalance = uint256($._balanceCheckpoints[from].latest());
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }

            // Overflow not possible: value <= fromBalance <= totalSupply <= maxSupply
            // Use snapshot for balance
            $._balanceCheckpoints[from].push(lastSnapshotClock, currentClock, _subtractUnchecked, lastSnapshotClock);
        }

        if (to == address(0)) {
            // For burn, decrease the total supply
            // Overflow not possible: value <= totalSupply or value <= fromBalance <= totalSupply
            // No snapshot optimization for totalSupply (for ERC20Votes)
            $._totalSupplyCheckpoints.push(currentClock, _subtractUnchecked, value);
        } else {
            // Overflow not possible: balance + value is at most totalSupply
            // Use snapshot for balance
            $._balanceCheckpoints[to].push(lastSnapshotClock, currentClock, _addUnchecked, value);
        }

        emit Transfer(from, to, value);
    }

    /**
     * @dev Checks the provided snapshot ID, reverts if it does not exist. Returns the lastSnapshotId and
     * lastSnapshotClock read from the packed storage slot.
     */
    function _checkSnapshotId(
        ERC20SnapshotsStorage storage $,
        uint256 snapshotId
    ) internal view returns (
        uint256 lastSnapshotId,
        uint256 lastSnapshotClock
    ) {
        // Just read both values here as a gas optimization for some operations
        lastSnapshotClock = $._lastSnapshotClock;
        lastSnapshotId = $._lastSnapshotId;
        if (snapshotId > lastSnapshotId) {
            revert ERC20SnapshotIdDoesNotExist(lastSnapshotId, snapshotId);
        }
    }

    function _add(uint256 a, uint256 b) internal pure returns (uint256 result) {
        result = a + b;
    }

    function _subtract(uint256 a, uint256 b) internal pure returns (uint256 result) {
        result = a - b;
    }

    function _addUnchecked(uint256 a, uint256 b) internal pure returns (uint256 result) {
        unchecked {
            result = a + b;
        }
    }

    function _subtractUnchecked(uint256 a, uint256 b) internal pure returns (uint256 result) {
        unchecked {
            result = a - b;
        }
    }

}