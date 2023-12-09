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
 * Maintains EIP7201 storage namespacing for upgradeability.
 */
abstract contract ERC20SnapshotsUpgradeable is
    ContextUpgradeable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    ERC165Upgradeable,
    IERC20Snapshots
{
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

    function _getERC20SnapshotsStorage() private view returns (ERC20SnapshotsStorage storage $) {
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
        return SafeCast.toUint48(block.number);
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
     * @inheritdoc ERC20Upgradeable
     * @dev This function is modified to follow the exact same logic as the _update function in the original
     * ERC20Upgradeable contract, but using checkpoints for balances and total supply.
     */
    function _update(address from, address to, uint256 value) internal virtual override {
        ERC20SnapshotsStorage storage $ = _getERC20SnapshotsStorage();
        if (from == address(0)) {
            // Increase the total supply, but not past the maxSupply
            (,uint256 newTotalSupply) = _writeCheckpoint($._totalSupplyCheckpoints, _add, value);
            uint256 currentMaxSupply = maxSupply();
            if (newTotalSupply > currentMaxSupply) {
                revert ERC20MaxSupplyOverflow(currentMaxSupply, newTotalSupply);
            }
        } else {
            uint256 fromBalance = uint256($._balanceCheckpoints[from].latest());
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                // Overflow not possible: value <= fromBalance <= totalSupply <= maxSupply
                _writeCheckpoint($._balanceCheckpoints[from], _subtract, value);
            }
        }

        if (to == address(0)) {
            unchecked {
                // Overflow not possible: value <= totalSupply or value <= fromBalance <= totalSupply
                _writeCheckpoint($._totalSupplyCheckpoints, _subtract, value);
            }
        } else {
            unchecked {
                // Overflow not possible: balance + value is at most totalSupply
                _writeCheckpoint($._balanceCheckpoints[to], _add, value);
            }
        }

        emit Transfer(from, to, value);
    }

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

    function _writeCheckpoint(
        SnapshotCheckpoints.Trace208 storage store,
        function(uint256, uint256) view returns (uint256) op,
        uint256 delta
    ) internal returns (uint256 oldWeight, uint256 newWeight) {
        return store.push(clock(), SafeCast.toUint208(op(store.latest(), delta)));
    }

    function _add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }

    function _subtract(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }

}