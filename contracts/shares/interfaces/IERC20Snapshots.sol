// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";

/**
 * @dev Additional interface methods for {ERC20BalanceSnapshots}.
 */
interface IERC20Snapshots is IERC20, IERC6372 {

    event SnapshotCreated(
        uint256 indexed snapshotId,
        uint256 indexed snapshotClock
    );

    error ERC6372InconsistentClock();
    error ERC20SnapshotAlreadyScheduled();
    error ERC20SnapshotIdDoesNotExist(uint256 lastSnapshotId, uint256 providedSnapshotId);
    error ERC20MaxSupplyOverflow(uint256 maxSupply, uint256 resultingSupply);

    /**
     * Creates a new snapshot for the current clock value, creating a historical record of all account balances at the
     * time of this snapshot's creation. Returns the ID of the newly created snapshot.
     */
    function createSnapshot() external returns (uint256 _snapshotId);

    /**
     * Returns the ID of the most recent snapshot.
     */
    function getLastSnapshotId() external view returns (uint256 _lastSnapshotId);

    /**
     * Returns the clock value for the specified snapshot ID. Reverts if the snapshot ID does not exist.
     */
    function getSnapshotClock(uint256 snapshotId) external view returns (uint256 _snapshotClock);

    /**
     * @dev Maximum token supply. Should default to (and never be greater than) `type(uint208).max` (2^208^ - 1).
     */
    function maxSupply() external view returns (uint256);

    /**
     * Returns the account balance at the specified snapshot ID. Reverts
     */
    function getBalanceAtSnapshot(address account, uint256 snapshotId) external view returns (uint256 accountBalance);

    /**
     * @dev Returns the total supply of votes available at a specific snapshot ID in the past. If the `clock()` is
     * configured to use block numbers, this will return the value the end of the block that the snapshot was created.
     */
    function getTotalSupplyAtSnapshot(uint256 snapshotId) external view returns (uint256);

}