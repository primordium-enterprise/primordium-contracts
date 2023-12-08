// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title A library to keep historical track of sequential checkpoints, with option for eliminating new checkpoint
 * writes between snapshots.
 */
library SnapshotCheckpoints {
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

    /**
     * @dev Pushes a (`key`, `value`) pair into a Trace208 so that it is stored as the checkpoint.
     *
     * Returns previous value and new value.
     *
     * IMPORTANT: Never accept `key` as a user input, since an arbitrary `type(uint48).max` key set will disable the
     * library.
     */
    function push(Trace208 storage self, uint48 key, uint208 value) internal returns (uint208, uint208) {
        uint256 len = self._checkpointsLength;

        if (len > 0) {
            // Copying to memory is important here.
            Checkpoint208 memory last = _unsafeAccess(self, len - 1);

            // Checkpoint keys must be non-decreasing.
            if (last._key > key) {
                revert CheckpointUnorderedInsertion();
            }

            // Update or push new checkpoint
            if (last._key == key) {
                _unsafeAccess(self, len - 1)._value = value;
            } else {
                self._checkpointsLength = len + 1;
                Checkpoint208 storage newCheckpoint = _unsafeAccess(self, len);
                newCheckpoint._key = key;
                newCheckpoint._value = value;
            }
            return (last._value, value);
        } else {
            // Skip the first checkpoint, leaving it as an actual zero
            self._checkpointsLength = 2;
            Checkpoint208 storage newCheckpoint = _unsafeAccess(self, 1);
            newCheckpoint._key = key;
            newCheckpoint._value = value;
            return (0, value);
        }
    }

    /**
     * @dev Returns the value in the first (oldest) checkpoint with key greater or equal than the search key, or zero if
     * there is none.
     */
    function lowerLookup(Trace208 storage self, uint48 key) internal view returns (uint208 value) {
        uint256 len = self._checkpointsLength;
        if (len > 0) {
            uint256 pos = _lowerBinaryLookup(self, key, 0, len);
            value = _unsafeAccess(self, pos)._value;
        }
    }

    /**
     * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
     * if there is none.
     */
    function upperLookup(Trace208 storage self, uint48 key) internal view returns (uint208 value) {
        uint256 len = self._checkpointsLength;
        if (len > 0) {
            uint256 pos = _upperBinaryLookup(self, key, 0, len);
            value = _unsafeAccess(self, pos)._value;
        }
    }

    /**
     * @dev Returns the value in the last (most recent) checkpoint with key lower or equal than the search key, or zero
     * if there is none.
     *
     * NOTE: This is a variant of {upperLookup} that is optimised to find "recent" checkpoint (checkpoints with high
     * keys).
     */
    function upperLookupRecent(Trace208 storage self, uint48 key) internal view returns (uint208 value) {
        uint256 len = self._checkpointsLength;

        if (len > 0) {
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
            value = _unsafeAccess(self, pos)._value;
        }
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
        uint256 pos = self._checkpointsLength;
        if (pos == 0) {
            return (false, 0, 0);
        } else {
            Checkpoint208 memory ckpt = _unsafeAccess(self, pos - 1);
            return (true, ckpt._key, ckpt._value);
        }
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
    function at(Trace208 storage self, uint32 pos) internal view returns (Checkpoint208 memory) {
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
     * WARNING: `high` should not be greater than the array's length, and should never be zero.
     */
    function _upperBinaryLookup(
        Trace208 storage self,
        uint48 key,
        uint256 low,
        uint256 high
    ) private view returns (uint256) {
        while (low < high) {
            uint256 mid = Math.average(low, high);
            if (_unsafeAccess(self, mid)._key > key) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }
        return high - 1;
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
    ) private view returns (uint256) {
        while (low < high) {
            uint256 mid = Math.average(low, high);
            if (_unsafeAccess(self, mid)._key < key) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }
        return high;
    }

    /**
     * @dev Access an element of the mapping without a bounds check. The position is assumed to be within bounds.
     */
    function _unsafeAccess(
        Trace208 storage self,
        uint256 pos
    ) private pure returns (Checkpoint208 storage result) {
        assembly {
            mstore(0, pos)
            mstore(0x20, add(self.slot, 0x01))
            result.slot := keccak256(0, 0x40)
        }
    }
}