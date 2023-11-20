// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";

abstract contract ClockUtils is IERC6372 {

    /// @dev The seconds per block, set in the constructor based on the chain used.
    uint256 private immutable SECONDS_PER_BLOCK;

    constructor(uint256 secondsPerBlock) {
        SECONDS_PER_BLOCK = secondsPerBlock > 0 ? secondsPerBlock : 12; // assumes 12 seconds per block
    }

    function clock() public view virtual returns (uint48);

    function _transformBlockDuration(uint256 durationInBlocks) internal view returns (uint256 duration) {
        duration = _transformBlockDuration(durationInBlocks, _clockUsesTimestamps());
    }

    /// @dev Returns the provided durationInBlocks as a duration in seconds IF usesTimestamps is true
    function _transformBlockDuration(
        uint256 durationInBlocks,
        bool usesTimestamps
    ) internal view returns (uint256 duration) {
        duration = usesTimestamps ? durationInBlocks * SECONDS_PER_BLOCK : durationInBlocks;
    }

    function _clockUsesTimestamps() internal view returns (bool) {
        return clock() == block.timestamp;
    }

}