// SPDX-License-Identifier: MIT
// Primordium Contracts
// Based on OpenZeppelin Contracts (last updated v5.0.0) (utils/structs/Checkpoints.sol)

pragma solidity ^0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title A library to keep historical track of sequential checkpoints, with option to optimize gas between snapshots
 * by avoiding pushing new checkpoints unnecessarily.
 * @author Ben Jett - @BCJdevelopment
 * @dev Modified from OpenZeppelin's procedurally generated {Checkpoints.sol} contract:
 * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v5.0/contracts/utils/structs/Checkpoints.sol
 *
 * Modifications:
 * - Uses mapping instead of array for storing checkpoints
 * - Push functions with function ops as arguments, for gas optimized storage reads and writes when updating values
 * - Some assembly optimizations here and there
 */
library SnapshotCheckpoints {
    using SafeCast for uint256;

    /**
     * @dev A value was attempted to be inserted on a past checkpoint.
     */
    error CheckpointUnorderedInsertion();

    /**
     * @dev A non-existing checkpoint was attempted to be accessed.
     */
    error CheckpointOutOfBounds();

    struct Trace208 {
        uint256 _checkpointsLength;
        mapping(uint256 index => Checkpoint208) _checkpoints;
    }

    struct Checkpoint208 {
        uint48 _key;
        uint208 _value;
    }

    uint48 private constant MAX_KEY = type(uint48).max;

    uint256 private constant MASK_UINT48 = 0xffffffffffff;

    /**
     * @dev Updates the (`key`, `value`) pair into a Trace208 so that it is stored as a checkpoint. If the `snapshotKey`
     * is less than the most recent checkpoint's key, then the recent checkpoint will be overwritten with the new key
     * and value to optimize gas costs between snapshots.
     *
     * Returns previous value and new value.
     *
     * IMPORTANT: Never accept `key` as a user input, since an arbitrary `type(uint48).max` key set will disable the
     * library.
     */
    function push(
        Trace208 storage self,
        uint48 snapshotKey,
        uint48 key,
        uint208 value
    )
        internal
        returns (uint208, uint208)
    {
        (uint256 len, Checkpoint208 memory lastCkpt) = _latestCheckpoint(self);
        return _insert(self, snapshotKey, key, value, len, lastCkpt);
    }

    /**
     * @dev Same as above (gas optimized snapshot overwrite), but performs the provided op function to calculate the new
     * value. The op takes the last checkpoint value and the delta as arguments to return the updated value.
     */
    function push(
        Trace208 storage self,
        uint48 snapshotKey,
        uint48 key,
        function(uint256, uint256) view returns (uint256) op,
        uint256 delta
    )
        internal
        returns (uint208, uint208)
    {
        (uint256 len, Checkpoint208 memory lastCkpt) = _latestCheckpoint(self);
        return _insert(self, snapshotKey, key, op(lastCkpt._value, delta).toUint208(), len, lastCkpt);
    }

    /**
     * @dev Ignores any snapshots and pushes a (`key`, `value`) pair into a Trace208 so that it is stored as a new
     * checkpoint.
     *
     * Returns previous value and new value.
     *
     * IMPORTANT: Never accept `key` as a user input, since an arbitrary `type(uint48).max` key set will disable the
     * library.
     */
    function push(Trace208 storage self, uint48 key, uint208 value) internal returns (uint208, uint208) {
        return push(self, MAX_KEY, key, value);
    }

    /**
     * @dev Same as above (ignores snapshots, pushes a new pair), but performs the provided op function to calculate the
     * new value. The op takes the last checkpoint value and the delta as arguments to return the updated value.
     */
    function push(
        Trace208 storage self,
        uint48 key,
        function(uint256, uint256) view returns (uint256) op,
        uint256 delta
    )
        internal
        returns (uint208, uint208)
    {
        return push(self, MAX_KEY, key, op, delta);
    }

    /**
     * @dev Returns the value in the first (oldest) checkpoint with key greater or equal than the search key, or zero if
     * there is none.
     */
    function lowerLookup(Trace208 storage self, uint48 key) internal view returns (uint208) {
        uint256 len = self._checkpointsLength;
        uint256 pos = _lowerBinaryLookup(self, key, 0, len);
        return pos == len ? 0 : _unsafeAccess(self, pos)._value;
    }

    /**
     * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
     * if there is none.
     */
    function upperLookup(Trace208 storage self, uint48 key) internal view returns (uint208) {
        uint256 len = self._checkpointsLength;
        uint256 pos = _upperBinaryLookup(self, key, 0, len);
        return pos == 0 ? 0 : _unsafeAccess(self, pos - 1)._value;
    }

    /**
     * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
     * if there is none.
     *
     * NOTE: This is a variant of {upperLookup} that is optimised to find "recent" checkpoint (checkpoints with high
     * keys).
     */
    function upperLookupRecent(Trace208 storage self, uint48 key) internal view returns (uint208) {
        uint256 len = self._checkpointsLength;

        uint256 low = 0;
        uint256 high = len;

        if (len > 5) {
            uint256 mid = len - Math.sqrt(len);
            if (key < _unsafeAccess(self, mid)._key) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        uint256 pos = _upperBinaryLookup(self, key, low, high);
        return pos == 0 ? 0 : _unsafeAccess(self, pos - 1)._value;
    }

    /**
     * @dev Optimizes the search for the most recent snapshot. Checks the most recent two checkpoints for a key lower or
     * equal to the search key, and defaults to {upperLookupRecent} if a match isn't found.
     *
     * NOTE: Only use this function if the provided key is the most recent snapshot.
     */
    function upperLookupMostRecentSnapshot(Trace208 storage self, uint48 key) internal view returns (uint208) {
        uint256 len = self._checkpointsLength;

        uint256 high = len;

        if (len > 1) {
            // Check the most recent checkpoint, and return if the key matches
            Checkpoint208 memory checkpoint = _unsafeAccess(self, high - 1);
            if (checkpoint._key <= key) {
                return checkpoint._value;
            } else {
                // Check the second most recent checkpoint (it should match if the key is the most recent snapshot)
                high -= 1;
                checkpoint = _unsafeAccess(self, high - 1);
                if (checkpoint._key <= key) {
                    return checkpoint._value;
                }
            }
        }

        // If the checkpoint still wasn't found, perform an upper lookup, optimized for recent
        uint256 low = 0;
        if (high > 5) {
            uint256 mid = len - Math.sqrt(len);
            if (key < _unsafeAccess(self, mid)._key) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        uint256 pos = _upperBinaryLookup(self, key, low, high);
        return pos == 0 ? 0 : _unsafeAccess(self, pos - 1)._value;
    }

    /**
     * @dev Returns the value in the most recent checkpoint, or zero if there are no checkpoints.
     */
    function latest(Trace208 storage self) internal view returns (uint208) {
        uint256 len = self._checkpointsLength;
        return len == 0 ? 0 : _unsafeAccess(self, len - 1)._value;
    }

    /**
     * @dev Returns whether there is a checkpoint in the structure (i.e. it is not empty), and if so the key and value
     * in the most recent checkpoint.
     */
    function latestCheckpoint(Trace208 storage self) internal view returns (bool exists, uint48 _key, uint208 _value) {
        (uint256 len, Checkpoint208 memory ckpt) = _latestCheckpoint(self);
        exists = len > 0;
        return (exists, ckpt._key, ckpt._value);
    }

    /**
     * @dev Returns the number of checkpoint.
     */
    function length(Trace208 storage self) internal view returns (uint256) {
        return self._checkpointsLength;
    }

    /**
     * @dev Returns checkpoint at given position.
     */
    function at(Trace208 storage self, uint48 pos) internal view returns (Checkpoint208 memory) {
        if (pos >= self._checkpointsLength) {
            revert CheckpointOutOfBounds();
        }
        return self._checkpoints[pos];
    }

    /**
     * @dev Return the index of the last (most recent) checkpoint with key lower or equal than the search key, or `high`
     * if there is none. `low` and `high` define a section where to do the search, with inclusive `low` and exclusive
     * `high`.
     *
     * WARNING: `high` should not be greater than the array's length.
     */
    function _upperBinaryLookup(
        Trace208 storage self,
        uint48 key,
        uint256 low,
        uint256 high
    )
        private
        view
        returns (uint256)
    {
        assembly ("memory-safe") {
            // Store mapping slot in scratch space for repeated hashing
            mstore(0x20, add(self.slot, 0x01))
            for {} lt(low, high) {} {
                // mstore mid in scratch space at byte 0 (for hashing)
                // mid = avg(low, high), where avg = (low & high) + (low ^ high) / 2
                mstore(0, add(and(low, high), div(xor(low, high), 2)))
                // if (_checkpoints[mid]._key > key)
                switch gt(and(sload(keccak256(0, 0x40)), MASK_UINT48), key)
                case 1 { high := mload(0) }
                // high = mid
                default { low := add(mload(0), 0x01) } // low = mid + 1
            }
        }
        return high;
    }

    /**
     * @dev Return the index of the first (oldest) checkpoint with key is greater or equal than the search key, or
     * `high` if there is none. `low` and `high` define a section where to do the search, with inclusive `low` and
     * exclusive `high`.
     *
     * WARNING: `high` should not be greater than the array's length.
     */
    function _lowerBinaryLookup(
        Trace208 storage self,
        uint48 key,
        uint256 low,
        uint256 high
    )
        private
        view
        returns (uint256)
    {
        assembly ("memory-safe") {
            // Store mapping slot in scratch space for repeated hashing
            mstore(0x20, add(self.slot, 0x01))
            for {} lt(low, high) {} {
                // mstore mid in scratch space at byte 0 (for hashing)
                // mid = avg(low, high), where avg = (low & high) + (low ^ high) / 2
                mstore(0, add(and(low, high), div(xor(low, high), 2)))
                // if (_checkpoints[mid]._key < key)
                switch lt(and(sload(keccak256(0, 0x40)), MASK_UINT48), key)
                case 1 { low := add(mload(0), 0x01) }
                // low = mid + 1
                default { high := mload(0) }
            }
        }
        return high;
    }

    function _latestCheckpoint(Trace208 storage self) private view returns (uint256 len, Checkpoint208 memory ckpt) {
        len = self._checkpointsLength;
        if (len > 0) {
            ckpt = _unsafeAccess(self, len - 1);
        }
    }

    /**
     * @dev IMPORTANT: This function assumes the "len" and "lastCkpt" refer to the checkpoints length, and the most
     * recent checkpoint cached in memory, respectively.
     */
    function _insert(
        Trace208 storage self,
        uint48 snapshotKey,
        uint48 key,
        uint208 value,
        uint256 len,
        Checkpoint208 memory lastCkpt
    )
        private
        returns (uint208, uint208)
    {
        if (len > 0) {
            // Checkpoint keys must be non-decreasing.
            if (lastCkpt._key > key) {
                revert CheckpointUnorderedInsertion();
            }

            // Update or push new checkpoint (can update if last key is greater than the provided snapshot key)
            if (lastCkpt._key == key || lastCkpt._key > snapshotKey) {
                Checkpoint208 storage _last = _unsafeAccess(self, len - 1);
                _last._key = key;
                _last._value = value;
            } else {
                self._checkpointsLength = len + 1;
                Checkpoint208 storage _next = _unsafeAccess(self, len);
                _next._key = key;
                _next._value = value;
            }
            return (lastCkpt._value, value);
        } else {
            // Initialize the first checkpoint
            self._checkpointsLength = 1;
            Checkpoint208 storage _next = _unsafeAccess(self, 0);
            _next._key = key;
            _next._value = value;
            return (0, value);
        }
    }

    /**
     * @dev Access an element of the mapping without a bounds check. The position is assumed to be within bounds.
     */
    function _unsafeAccess(Trace208 storage self, uint256 pos) private pure returns (Checkpoint208 storage result) {
        assembly {
            mstore(0, pos)
            mstore(0x20, add(self.slot, 0x01))
            result.slot := keccak256(0, 0x40)
        }
    }
}
